// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageShiftDialogs on _SalesPageState {
  Future<void> _openSaleDrawerDialog(_SaleShiftStatus status) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: '0');
    final drawers = status.drawers;
    final sources = status.cashLocations
        .where((item) => item.type != 'cash_drawer')
        .toList(growable: false);
    String selectedDrawerId = (status.drawer?.id ?? '').isNotEmpty
        ? status.drawer!.id
        : (drawers.isNotEmpty ? drawers.first.id : '');
    String selectedFundingId = sources.isNotEmpty ? sources.first.id : '';
    bool useFundingSource = sources.isNotEmpty;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: Text(tr.text('open_cash_shift')),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: selectedDrawerId.isEmpty
                              ? null
                              : selectedDrawerId,
                          decoration: InputDecoration(
                              labelText: tr.text('cash_drawer')),
                          items: drawers
                              .map((item) => DropdownMenuItem(
                                  value: item.id, child: Text(item.name)))
                              .toList(),
                          onChanged: (value) => setDialogState(
                              () => selectedDrawerId = value ?? '')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: tr.text('opening_amount'))),
                      if (sources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tr.text('transfer_opening_amount')),
                            value: useFundingSource,
                            onChanged: (value) =>
                                setDialogState(() => useFundingSource = value)),
                        if (useFundingSource)
                          DropdownButtonFormField<String>(
                              initialValue: selectedFundingId.isEmpty
                                  ? null
                                  : selectedFundingId,
                              decoration: InputDecoration(
                                  labelText: tr.text('funding_source')),
                              items: sources
                                  .map((item) => DropdownMenuItem(
                                      value: item.id, child: Text(item.name)))
                                  .toList(),
                              onChanged: (value) => setDialogState(
                                  () => selectedFundingId = value ?? ''))
                      ]
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr.text('cancel'))),
                      FilledButton(
                          onPressed: selectedDrawerId.isEmpty
                              ? null
                              : () => Navigator.pop(dialogContext, true),
                          child: Text(tr.text('open')))
                    ])));
    try {
      if (confirmed == true) {
        final drawer =
            drawers.firstWhere((item) => item.id == selectedDrawerId);
        final activeUser = widget.store.activeUser;
        await AccountingService.openCashDrawer(
            authorization: widget.store,
            drawerNo: drawer.name,
            cashLocationId: drawer.id,
            fundingLocationId: useFundingSource ? selectedFundingId : '',
            openingBalance: double.tryParse(controller.text.trim()) ?? 0,
            openedBy: _activeUserDisplayName(activeUser),
            openedByUserId: activeUser?.id ?? '',
            storeId: widget.store.appIdentity.storeId,
            branchId: widget.store.appIdentity.branchId,
            deviceId: widget.store.appIdentity.deviceId);
        if (!mounted) return;
        setState(() => _cashShiftRefreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('cash_shift_opened'))));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizeRuntimeMessage(error.toString(), tr))));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _closeSaleDrawerDialog(
      AdvancedAccountingItem session, _SaleShiftStatus status) async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    final expected =
        await AccountingService.calculateCashDrawerExpectedCash(session.id);
    if (!mounted) return;
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final notes = TextEditingController();
    final transferTargets = status.cashLocations
        .where((item) => item.id != session.referenceId)
        .toList(growable: false);
    final activeUser = widget.store.activeUser;
    final handoverUsers = widget.store.users
        .where((user) => user.isActive && user.id != (activeUser?.id ?? ''))
        .toList(growable: false);
    String closeMode = 'keep_drawer';
    String transferToId = '';
    String nextUserId = '';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: Text(tr.text('close_handover_shift')),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text(
                              '${tr.text('expected')}: ${formatUsdReferenceAmount(expected, widget.store.storeProfile)}'),
                          const SizedBox(height: 12),
                          TextField(
                              controller: counted,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: tr.text('counted_amount'))),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              initialValue: closeMode,
                              decoration: InputDecoration(
                                  labelText: tr.text('close_action')),
                              items: [
                                DropdownMenuItem(
                                    value: 'keep_drawer',
                                    child:
                                        Text(tr.text('close_only_keep_cash'))),
                                DropdownMenuItem(
                                    value: 'transfer_location',
                                    child: Text(
                                        tr.text('close_and_transfer_cash'))),
                                DropdownMenuItem(
                                    value: 'handover_user',
                                    child: Text(
                                        tr.text('handover_and_open_shift')))
                              ],
                              onChanged: (value) => setDialogState(
                                  () => closeMode = value ?? closeMode)),
                          if (closeMode == 'transfer_location') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                initialValue:
                                    transferToId.isEmpty ? null : transferToId,
                                decoration: InputDecoration(
                                    labelText:
                                        tr.text('receiving_drawer_vault')),
                                items: transferTargets
                                    .map((item) => DropdownMenuItem(
                                        value: item.id, child: Text(item.name)))
                                    .toList(),
                                onChanged: (value) => setDialogState(
                                    () => transferToId = value ?? ''))
                          ],
                          if (closeMode == 'handover_user') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                initialValue:
                                    nextUserId.isEmpty ? null : nextUserId,
                                decoration: InputDecoration(
                                    labelText: tr.text('receiving_employee')),
                                items: handoverUsers
                                    .map((user) => DropdownMenuItem(
                                        value: user.id,
                                        child:
                                            Text(_activeUserDisplayName(user))))
                                    .toList(),
                                onChanged: (value) => setDialogState(
                                    () => nextUserId = value ?? '')),
                            const SizedBox(height: 6),
                            Text(tr.text('handover_shift_explanation'),
                                style:
                                    Theme.of(dialogContext).textTheme.bodySmall)
                          ],
                          const SizedBox(height: 12),
                          TextField(
                              controller: notes,
                              decoration:
                                  InputDecoration(labelText: tr.text('notes')))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr.text('cancel'))),
                      FilledButton(
                          onPressed: (closeMode == 'transfer_location' &&
                                      transferToId.isEmpty) ||
                                  (closeMode == 'handover_user' &&
                                      nextUserId.isEmpty)
                              ? null
                              : () => Navigator.pop(dialogContext, true),
                          child: Text(tr.text('close')))
                    ])));
    try {
      if (confirmed == true) {
        final countedAmount = double.tryParse(counted.text.trim()) ?? 0;
        final activeUserName = _activeUserDisplayName(activeUser);
        AppUser? nextUser;
        for (final user in handoverUsers) {
          if (user.id == nextUserId) {
            nextUser = user;
            break;
          }
        }
        String transferTargetName = '';
        for (final location in transferTargets) {
          if (location.id == transferToId) transferTargetName = location.name;
        }
        final nextUserName =
            nextUser == null ? '' : _activeUserDisplayName(nextUser);
        final effectiveNotes = [
          notes.text.trim(),
          if (closeMode == 'transfer_location')
            'تحويل النقد بعد الإغلاق إلى $transferTargetName',
          if (closeMode == 'handover_user') 'تسليم الوردية إلى $nextUserName'
        ].where((part) => part.trim().isNotEmpty).join(' • ');
        await AccountingService.closeCashDrawer(
            authorization: widget.store,
            sessionId: session.id,
            countedCash: countedAmount,
            closedBy: activeUserName,
            closedByUserId: activeUser?.id ?? '',
            notes: effectiveNotes,
            depositToLocationId:
                closeMode == 'transfer_location' ? transferToId : '');
        if (closeMode == 'handover_user' &&
            nextUser != null &&
            session.referenceId.trim().isNotEmpty) {
          await AccountingService.openCashDrawer(
              authorization: widget.store,
              drawerNo: session.name,
              cashLocationId: session.referenceId,
              openingBalance: countedAmount,
              openedBy: nextUserName,
              openedByUserId: nextUser.id,
              storeId: widget.store.appIdentity.storeId,
              branchId: widget.store.appIdentity.branchId,
              deviceId: widget.store.appIdentity.deviceId);
        }
        if (!mounted) return;
        setState(() => _cashShiftRefreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('cash_shift_updated'))));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizeRuntimeMessage(error.toString(), tr))));
    } finally {
      counted.dispose();
      notes.dispose();
    }
  }
}
