part of 'cash_page.dart';

extension _CashPageStatePart3 on _CashPageState {

  Future<void> _cashOperationDialog({
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem currentSession,
    required String type,
  }) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    final allAccounts = await AccountingService.listAccounts(activeOnly: true);
    if (!mounted) return;

    final activeAccounts = allAccounts
        .where((account) => account.isActive)
        .toList(growable: false);
    final childrenByParent = <String, List<AccountingAccount>>{};
    for (final account in activeAccounts) {
      final parentId = account.parentId.trim();
      if (parentId.isEmpty) continue;
      childrenByParent
          .putIfAbsent(parentId, () => <AccountingAccount>[])
          .add(account);
    }

    List<AccountingAccount> postableDescendants(String parentId) {
      final result = <AccountingAccount>[];
      final visited = <String>{};
      final pending = <AccountingAccount>[
        ...?childrenByParent[parentId],
      ];
      while (pending.isNotEmpty) {
        final account = pending.removeLast();
        if (!visited.add(account.id)) continue;
        pending.addAll(
            childrenByParent[account.id] ?? const <AccountingAccount>[]);
        if (account.subtype == 'group' ||
            account.code == currentDrawer.accountCode) {
          continue;
        }
        result.add(account);
      }
      result.sort((a, b) => a.code.compareTo(b.code));
      return result;
    }

    final parentAccounts = activeAccounts
        .where((account) => postableDescendants(account.id).isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.code.compareTo(b.code));
    if (parentAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              tr,
              'No account with postable sub-accounts is available.',
              'لا يوجد حساب يحتوي على حسابات فرعية قابلة للترحيل.',
            ),
          ),
        ),
      );
      return;
    }

    final amountController = TextEditingController();
    final notesController = TextEditingController();
    AccountingAccount? selectedParent;
    AccountingAccount? selectedCounterpart;
    final title = switch (type) {
      'cash_deposit' => _l(tr, 'Cash deposit', 'إيداع نقدي'),
      'cash_withdrawal' => _l(tr, 'Cash withdrawal', 'سحب نقدي'),
      'expense' => _l(tr, 'Cash expense', 'مصروف نقدي'),
      _ => _l(tr, 'Cash operation', 'عملية نقدية'),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                    '${_l(tr, 'Cash location', 'موقع النقدية')}: ${currentDrawer.name}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountingAccount>(
                initialValue: selectedParent,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _l(tr, 'Counterpart account', 'الحساب المقابل'),
                  helperText: _l(
                    tr,
                    'Choose the account family first.',
                    'اختر الحساب الرئيسي أولاً.',
                  ),
                ),
                items: parentAccounts
                    .map(
                      (account) => DropdownMenuItem<AccountingAccount>(
                        value: account,
                        child: Text(
                          '${account.code} - ${account.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() {
                  selectedParent = value;
                  selectedCounterpart = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountingAccount>(
                key: ValueKey<String?>(selectedParent?.id),
                initialValue: selectedCounterpart,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _l(tr, 'Derived account', 'الحساب المشتق'),
                  helperText: selectedParent == null
                      ? _l(
                          tr,
                          'Select the parent account first.',
                          'اختر الحساب الرئيسي أولاً.',
                        )
                      : _l(
                          tr,
                          'Required. Posting will use this account only; no default account is used.',
                          'إلزامي. سيتم الترحيل على هذا الحساب فقط ولن يستخدم أي حساب افتراضي.',
                        ),
                ),
                items: selectedParent == null
                    ? const <DropdownMenuItem<AccountingAccount>>[]
                    : postableDescendants(selectedParent!.id)
                        .map(
                          (account) => DropdownMenuItem<AccountingAccount>(
                            value: account,
                            child: Text(
                              '${account.code} - ${account.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                onChanged: selectedParent == null
                    ? null
                    : (value) =>
                        setDialogState(() => selectedCounterpart = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr.text('amount')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: InputDecoration(labelText: tr.text('notes')),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: selectedCounterpart == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('post')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedCounterpart == null) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final notes = notesController.text.trim();
    final counterpartAccountId = selectedCounterpart!.id;
    amountController.dispose();
    notesController.dispose();
    if (amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(_l(tr, 'Enter a valid amount.', 'أدخل مبلغاً صالحاً.'))),
        );
      }
      return;
    }
    try {
      final user = widget.store.activeUser;
      final service = CashOperationService.current(authorization: widget.store);
      final args = (
        cashLocationId: currentDrawer.id,
        cashDrawerSessionId: currentSession.id,
        counterpartAccountId: counterpartAccountId,
        amount: amount,
        notes: notes,
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName
            : widget.store.currentRole,
        createdByUserId: user?.id ?? '',
        deviceId: widget.store.appIdentity.deviceId,
        branchId: widget.store.appIdentity.branchId,
        storeId: widget.store.appIdentity.storeId,
        idempotencyKey:
            'cash-ui-$type-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      if (type == 'cash_deposit') {
        await service.deposit(
          cashLocationId: args.cashLocationId,
          cashDrawerSessionId: args.cashDrawerSessionId,
          counterpartAccountId: args.counterpartAccountId,
          amount: args.amount,
          notes: args.notes,
          createdBy: args.createdBy,
          createdByUserId: args.createdByUserId,
          deviceId: args.deviceId,
          branchId: args.branchId,
          storeId: args.storeId,
          idempotencyKey: args.idempotencyKey,
        );
      } else if (type == 'cash_withdrawal') {
        await service.withdrawal(
          cashLocationId: args.cashLocationId,
          cashDrawerSessionId: args.cashDrawerSessionId,
          counterpartAccountId: args.counterpartAccountId,
          amount: args.amount,
          notes: args.notes,
          createdBy: args.createdBy,
          createdByUserId: args.createdByUserId,
          deviceId: args.deviceId,
          branchId: args.branchId,
          storeId: args.storeId,
          idempotencyKey: args.idempotencyKey,
        );
      } else {
        await service.expense(
          cashLocationId: args.cashLocationId,
          cashDrawerSessionId: args.cashDrawerSessionId,
          counterpartAccountId: args.counterpartAccountId,
          amount: args.amount,
          notes: args.notes,
          createdBy: args.createdBy,
          createdByUserId: args.createdByUserId,
          deviceId: args.deviceId,
          branchId: args.branchId,
          storeId: args.storeId,
          idempotencyKey: args.idempotencyKey,
        );
      }
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    }
  }

  Future<void> _cashTransferDialog({
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem currentSession,
    required String kind,
  }) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    final all =
        await AccountingService.listActiveCashLocations(includeBank: false);
    if (!mounted) return;
    var candidates = all
        .where((item) => item.id != currentDrawer.id)
        .toList(growable: false);
    if (kind == 'shift_transfer') {
      candidates = candidates
          .where((item) => item.type == 'cash_drawer')
          .toList(growable: false);
    } else {
      final preferred = candidates
          .where((item) => item.type != 'cash_drawer')
          .toList(growable: false);
      if (preferred.isNotEmpty) candidates = preferred;
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_l(tr, 'No eligible cash location was found.',
              'لا يوجد موقع نقدية مناسب للتحويل.'))));
      return;
    }
    String otherLocationId = candidates.first.id;
    String flow = 'out';
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(kind == 'shift_transfer'
              ? _l(tr, 'Shift transfer', 'تحويل شيفت')
              : _l(tr, 'Vault transfer', 'تحويل خزنة')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: flow,
              decoration:
                  InputDecoration(labelText: _l(tr, 'Direction', 'الاتجاه')),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                    value: 'out',
                    child: Text(
                        '${currentDrawer.name} → ${_l(tr, 'destination', 'الوجهة')}')),
                DropdownMenuItem(
                    value: 'in',
                    child: Text(
                        '${_l(tr, 'source', 'المصدر')} → ${currentDrawer.name}')),
              ],
              onChanged: (value) => setDialogState(() => flow = value ?? 'out'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: otherLocationId,
              decoration: InputDecoration(
                  labelText: flow == 'out'
                      ? _l(tr, 'To', 'إلى')
                      : _l(tr, 'From', 'من')),
              items: candidates
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) => setDialogState(
                  () => otherLocationId = value ?? otherLocationId),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr.text('amount'))),
            const SizedBox(height: 12),
            TextField(
                controller: notesController,
                decoration: InputDecoration(labelText: tr.text('notes'))),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_l(tr, 'Transfer', 'تحويل'))),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final notes = notesController.text.trim();
    amountController.dispose();
    notesController.dispose();
    if (amount <= 0) return;
    try {
      final other = candidates.firstWhere((item) => item.id == otherLocationId);
      final from = flow == 'out' ? currentDrawer : other;
      final to = flow == 'out' ? other : currentDrawer;
      String fromSessionId = flow == 'out' ? currentSession.id : '';
      String toSessionId = flow == 'in' ? currentSession.id : '';

      if (from.type == 'cash_drawer' && fromSessionId.isEmpty) {
        fromSessionId = await AccountingService.currentOpenCashDrawerSessionId(
          branchId: widget.store.appIdentity.branchId,
          cashLocationId: from.id,
        );
        if (fromSessionId.isEmpty) {
          throw StateError(_l(tr, 'The source cash drawer has no open shift.',
              'درج النقدية المصدر لا يملك شيفتاً مفتوحاً.'));
        }
      }
      if (to.type == 'cash_drawer' && toSessionId.isEmpty) {
        toSessionId = await AccountingService.currentOpenCashDrawerSessionId(
          branchId: widget.store.appIdentity.branchId,
          cashLocationId: to.id,
        );
        if (toSessionId.isEmpty) {
          throw StateError(_l(
              tr,
              'The destination cash drawer has no open shift.',
              'درج النقدية الوجهة لا يملك شيفتاً مفتوحاً.'));
        }
      }
      final user = widget.store.activeUser;
      await AccountingService.createCashTransfer(
        authorization: widget.store,
        fromLocationId: from.id,
        toLocationId: to.id,
        amount: amount,
        notes: notes,
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName
            : widget.store.currentRole,
        createdByUserId: user?.id ?? '',
        storeId: widget.store.appIdentity.storeId,
        branchId: widget.store.appIdentity.branchId,
        deviceId: widget.store.appIdentity.deviceId,
        fromSessionId: fromSessionId,
        toSessionId: toSessionId,
        transferKind: kind,
        idempotencyKey:
            'cash-ui-$kind-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizeRuntimeMessage(error.toString(), tr))));
    }
  }

  Future<void> _openDrawerDialog(
      BuildContext context, List<AdvancedAccountingItem> drawers) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    if (drawers.isEmpty) return;
    final controller = TextEditingController(text: '0');
    String selectedDrawerId = drawers.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr.text('open_cash_shift')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: selectedDrawerId,
              decoration: InputDecoration(labelText: tr.text('cash_drawer')),
              items: drawers
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) =>
                  setDialogState(() => selectedDrawerId = value ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr.text('opening_amount')),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed: selectedDrawerId.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(tr.text('open'))),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    try {
      final drawer = drawers.firstWhere((item) => item.id == selectedDrawerId);
      final activeUser = widget.store.activeUser;
      await AccountingService.openCashDrawer(
        authorization: widget.store,
        drawerNo: drawer.name,
        cashLocationId: drawer.id,
        openingBalance: double.tryParse(controller.text.trim()) ?? 0,
        openedBy: activeUser?.fullName.trim().isNotEmpty == true
            ? activeUser!.fullName
            : widget.store.currentRole,
        openedByUserId: activeUser?.id ?? '',
        storeId: widget.store.appIdentity.storeId,
        branchId: widget.store.appIdentity.branchId,
        deviceId: widget.store.appIdentity.deviceId,
      );
      _refresh();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _closeDrawerDialog(
      BuildContext context, AdvancedAccountingItem session) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    final expected =
        await AccountingService.calculateCashDrawerExpectedCash(session.id);
    if (!context.mounted) return;
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('close_handover_shift')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '${tr.text('expected')}: ${formatUsdReferenceAmount(expected, widget.store.storeProfile)}'),
          const SizedBox(height: 12),
          TextField(
              controller: counted,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  InputDecoration(labelText: tr.text('counted_amount'))),
          const SizedBox(height: 12),
          TextField(
              controller: notes,
              decoration: InputDecoration(labelText: tr.text('notes'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('close'))),
        ],
      ),
    );
    if (confirmed != true) {
      counted.dispose();
      notes.dispose();
      return;
    }
    try {
      final activeUser = widget.store.activeUser;
      await AccountingService.closeCashDrawer(
        authorization: widget.store,
        sessionId: session.id,
        countedCash: double.tryParse(counted.text.trim()) ?? 0,
        closedBy: activeUser?.fullName.trim().isNotEmpty == true
            ? activeUser!.fullName
            : widget.store.currentRole,
        closedByUserId: activeUser?.id ?? '',
        notes: notes.text.trim(),
      );
      _refresh();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      counted.dispose();
      notes.dispose();
    }
  }

  Future<List<CashLedgerTransaction>> _loadAllShiftMovements(
      String sessionId) async {
    final service = CashLedgerService.current();
    final result = <CashLedgerTransaction>[];
    var offset = 0;
    const pageSize = 500;
    while (true) {
      final page = await service.list(
        cashDrawerSessionId: sessionId,
        limit: pageSize,
        offset: offset,
      );
      result.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }
    return result;
  }
}
