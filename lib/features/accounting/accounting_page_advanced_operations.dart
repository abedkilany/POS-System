part of 'accounting_page.dart';

extension _AdvancedOperations on _AdvancedAccountingTabState {
  Future<void> _createPaymentAccountDialog() async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController();
    var type = 'bank';
    var isDefault = false;
    final accounts = (await AccountingService.listAccounts())
        .where((account) => account.isPostable)
        .toList();
    if (accounts.isEmpty) return;
    AccountingAccount? selected = accounts.firstWhere((a) => a.type == 'asset',
        orElse: () => accounts.first);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_payment_account')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr.text('name'))),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: tr.text('type')),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(tr.text('cash'))),
                  DropdownMenuItem(value: 'bank', child: Text(tr.text('bank'))),
                  DropdownMenuItem(value: 'card', child: Text(tr.text('card'))),
                  DropdownMenuItem(
                      value: 'wallet', child: Text(tr.text('wallet'))),
                  DropdownMenuItem(
                      value: 'cheque', child: Text(tr.text('cheque'))),
                  DropdownMenuItem(
                      value: 'other', child: Text(tr.text('other'))),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? type),
              ),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: selected,
                decoration:
                    InputDecoration(labelText: tr.text('mapped_account')),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a,
                        child: Text(
                            '${a.code} - ${_localizedAccountingName(a.name, tr)}'))
                ],
                onChanged: (v) => setDialogState(() => selected = v),
              ),
              CheckboxListTile(
                  value: isDefault,
                  onChanged: (v) =>
                      setDialogState(() => isDefault = v ?? false),
                  title: Text(tr.text('default_for_this_type'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create')))
          ],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      await AccountingService.createPaymentAccount(
          name: name.text,
          type: type,
          accountId: selected!.id,
          isDefault: isDefault);
      if (mounted) _refresh();
    }
  }

  Future<void> _createChequeDialog() async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final chequeNo = TextEditingController();
    final partyName = TextEditingController();
    final bankName = TextEditingController();
    final amount = TextEditingController(text: '0');
    var direction = 'received';
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('create_cheque')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: chequeNo,
                  decoration: InputDecoration(labelText: tr.text('cheque_no'))),
              DropdownButtonFormField<String>(
                initialValue: direction,
                decoration: InputDecoration(labelText: tr.text('direction')),
                items: [
                  DropdownMenuItem(
                      value: 'received', child: Text(tr.text('received'))),
                  DropdownMenuItem(
                      value: 'issued', child: Text(tr.text('issued'))),
                ],
                onChanged: (v) =>
                    setDialogState(() => direction = v ?? direction),
              ),
              TextField(
                  controller: partyName,
                  decoration:
                      InputDecoration(labelText: tr.text('party_name'))),
              TextField(
                  controller: bankName,
                  decoration: InputDecoration(labelText: tr.text('bank'))),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr.text('amount'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('create')))
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await AccountingService.createCheque(
        chequeNo: chequeNo.text,
        direction: direction,
        partyType: '',
        partyId: '',
        partyName: partyName.text,
        bankName: bankName.text,
        dueDate: DateTime.now(),
        amount: double.tryParse(amount.text) ?? 0,
      );
      if (mounted) _refresh();
    }
  }

  Future<void> _createMasterDataDialog(String table, String title) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: code,
              decoration: InputDecoration(labelText: tr.text('code'))),
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr.text('name'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('create')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.createSimpleMasterData(
          table: table, code: code.text, name: name.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _settleCheque(AdvancedAccountingItem item) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format(
            'clear_cheque', {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.format(
            'mark_cheque_cleared', {'amount': formatCurrency(item.balance)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('clear')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.settleCheque(chequeId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _bounceChequeDialog(AdvancedAccountingItem item) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format('bounce_cheque',
            {'name': _localizedAccountingName(item.name, tr)})),
        content: TextField(
            controller: reason,
            decoration: InputDecoration(labelText: tr.text('reason'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('bounce')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.bounceCheque(
          chequeId: item.id, reason: reason.text);
      if (mounted) _refresh();
    }
  }

  Future<void> _closePeriod(AdvancedAccountingItem item) async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.format(
            'close_period', {'name': _localizedAccountingName(item.name, tr)})),
        content: Text(tr.text('close_period_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('close_period')))
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.closeAccountingPeriod(periodId: item.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _createPeriodDialog() async {
    widget.store.requirePermission(AppPermission.accountingManage);
    final tr = AppLocalizations.of(context);
    final name = TextEditingController(text: tr.text('current_period'));
    final now = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('create_accounting_period')),
        content: TextField(
            controller: name,
            decoration: InputDecoration(labelText: tr.text('period_name'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('create'))),
        ],
      ),
    );
    if (confirmed == true) {
      await AccountingService.createAccountingPeriod(
        name: name.text,
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
      if (mounted) _refresh();
    }
  }
}
