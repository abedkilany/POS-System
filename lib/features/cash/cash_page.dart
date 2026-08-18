import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/cash_operation_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import 'cash_history_panel.dart';

class CashPage extends StatefulWidget {
  const CashPage({super.key, required this.store});

  final AppStore store;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  int _refreshKey = 0;
  void _refresh() { if (mounted) setState(() => _refreshKey++); }

  String get _deviceId => widget.store.appIdentity.deviceId.trim();
  String get _branchId => widget.store.appIdentity.branchId.trim();

  Future<void> _settleSaleInvoiceDialog(AdvancedAccountingItem currentDrawer) async {
    final tr = AppLocalizations.of(context);
    final openSales = widget.store.sales
        .where((sale) => !sale.isCancelled && sale.balanceDue > 0)
        .toList(growable: false);
    if (openSales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_sales'))),
      );
      return;
    }
    Sale selectedSale = openSales.first;
    final amountController = TextEditingController(text: selectedSale.balanceDue.toStringAsFixed(2));
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr.text('cash_in')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedSale.id,
                  decoration: InputDecoration(labelText: tr.text('sale')),
                  items: openSales
                      .map((sale) => DropdownMenuItem<String>(
                            value: sale.id,
                            child: Text('${sale.invoiceNo} • ${sale.customerName} • ${formatUsdReferenceAmount(sale.balanceDue, widget.store.storeProfile)}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    final found = openSales.where((sale) => sale.id == value).toList();
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selectedSale = found.first;
                      amountController.text = selectedSale.balanceDue.toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr.text('amount'),
                    helperText: '${tr.text('remaining_debt')}: ${formatUsdReferenceAmount(selectedSale.balanceDue, widget.store.storeProfile)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(labelText: tr.text('notes')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('post')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    if (!mounted) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0 || amount > selectedSale.balanceDue + 0.0001) {
      amountController.dispose();
      notesController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('invalid_cash_received_amount'))),
      );
      return;
    }
    try {
      await widget.store.settleSalePayment(
        saleId: selectedSale.id,
        amount: amount,
        paymentMethod: 'Cash',
        notes: notesController.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
    _refresh();
  }

  Future<void> _settlePurchaseInvoiceDialog(AdvancedAccountingItem currentDrawer) async {
    final tr = AppLocalizations.of(context);
    final openPurchases = widget.store.purchases
        .where((purchase) => !purchase.isCancelled && purchase.balanceDue > 0 && purchase.isReceived)
        .toList(growable: false);
    if (openPurchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_purchases'))),
      );
      return;
    }
    Purchase selectedPurchase = openPurchases.first;
    final amountController = TextEditingController(text: selectedPurchase.balanceDue.toStringAsFixed(2));
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr.text('cash_out')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedPurchase.id,
                  decoration: InputDecoration(labelText: tr.text('purchase')),
                  items: openPurchases
                      .map((purchase) => DropdownMenuItem<String>(
                            value: purchase.id,
                            child: Text('${purchase.purchaseNo} • ${purchase.supplierName} • ${formatUsdReferenceAmount(purchase.balanceDue, widget.store.storeProfile)}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    final found = openPurchases.where((purchase) => purchase.id == value).toList();
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selectedPurchase = found.first;
                      amountController.text = selectedPurchase.balanceDue.toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr.text('amount'),
                    helperText: '${tr.text('remaining_debt')}: ${formatUsdReferenceAmount(selectedPurchase.balanceDue, widget.store.storeProfile)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(labelText: tr.text('notes')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('post')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    if (!mounted) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0 || amount > selectedPurchase.balanceDue + 0.0001) {
      amountController.dispose();
      notesController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('invalid_paid_amount'))),
      );
      return;
    }
    try {
      await widget.store.settlePurchasePayment(
        purchaseId: selectedPurchase.id,
        amount: amount,
        paymentMethod: 'Cash',
        notes: notesController.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
    _refresh();
  }

  String _l(AppLocalizations tr, String en, String ar) => tr.isArabic ? ar : en;

  Future<void> _cashOperationDialog({
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem currentSession,
    required String type,
  }) async {
    final tr = AppLocalizations.of(context);
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final title = switch (type) {
      'cash_deposit' => _l(tr, 'Cash deposit', 'إيداع نقدي'),
      'cash_withdrawal' => _l(tr, 'Cash withdrawal', 'سحب نقدي'),
      'expense' => _l(tr, 'Cash expense', 'مصروف نقدي'),
      _ => _l(tr, 'Cash operation', 'عملية نقدية'),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('${_l(tr, 'Cash location', 'موقع النقدية')}: ${currentDrawer.name}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr.text('amount')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            decoration: InputDecoration(labelText: tr.text('notes')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr.text('post'))),
        ],
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
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l(tr, 'Enter a valid amount.', 'أدخل مبلغاً صالحاً.'))));
      return;
    }
    try {
      final user = widget.store.activeUser;
      final service = CashOperationService.current();
      final args = (
        cashLocationId: currentDrawer.id,
        cashDrawerSessionId: currentSession.id,
        amount: amount,
        notes: notes,
        createdBy: user?.fullName.trim().isNotEmpty == true ? user!.fullName : widget.store.currentRole,
        createdByUserId: user?.id ?? '',
        deviceId: widget.store.appIdentity.deviceId,
        branchId: widget.store.appIdentity.branchId,
        storeId: widget.store.appIdentity.storeId,
        idempotencyKey: 'cash-ui-$type-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      if (type == 'cash_deposit') {
        await service.deposit(
          cashLocationId: args.cashLocationId,
          cashDrawerSessionId: args.cashDrawerSessionId,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))));
    }
  }

  Future<void> _cashTransferDialog({
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem currentSession,
    required String kind,
  }) async {
    final tr = AppLocalizations.of(context);
    final all = await AccountingService.listActiveCashLocations(includeBank: false);
    if (!mounted) return;
    var candidates = all.where((item) => item.id != currentDrawer.id).toList(growable: false);
    if (kind == 'shift_transfer') {
      candidates = candidates.where((item) => item.type == 'cash_drawer').toList(growable: false);
    } else {
      final preferred = candidates.where((item) => item.type != 'cash_drawer').toList(growable: false);
      if (preferred.isNotEmpty) candidates = preferred;
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l(tr, 'No eligible cash location was found.', 'لا يوجد موقع نقدية مناسب للتحويل.'))));
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
          title: Text(kind == 'shift_transfer' ? _l(tr, 'Shift transfer', 'تحويل شيفت') : _l(tr, 'Vault transfer', 'تحويل خزنة')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: flow,
              decoration: InputDecoration(labelText: _l(tr, 'Direction', 'الاتجاه')),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'out', child: Text('${currentDrawer.name} → ${_l(tr, 'destination', 'الوجهة')}')),
                DropdownMenuItem(value: 'in', child: Text('${_l(tr, 'source', 'المصدر')} → ${currentDrawer.name}')),
              ],
              onChanged: (value) => setDialogState(() => flow = value ?? 'out'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: otherLocationId,
              decoration: InputDecoration(labelText: flow == 'out' ? _l(tr, 'To', 'إلى') : _l(tr, 'From', 'من')),
              items: candidates.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
              onChanged: (value) => setDialogState(() => otherLocationId = value ?? otherLocationId),
            ),
            const SizedBox(height: 12),
            TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr.text('amount'))),
            const SizedBox(height: 12),
            TextField(controller: notesController, decoration: InputDecoration(labelText: tr.text('notes'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_l(tr, 'Transfer', 'تحويل'))),
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
          throw StateError(_l(tr, 'The source cash drawer has no open shift.', 'درج النقدية المصدر لا يملك شيفتاً مفتوحاً.'));
        }
      }
      if (to.type == 'cash_drawer' && toSessionId.isEmpty) {
        toSessionId = await AccountingService.currentOpenCashDrawerSessionId(
          branchId: widget.store.appIdentity.branchId,
          cashLocationId: to.id,
        );
        if (toSessionId.isEmpty) {
          throw StateError(_l(tr, 'The destination cash drawer has no open shift.', 'درج النقدية الوجهة لا يملك شيفتاً مفتوحاً.'));
        }
      }
      final user = widget.store.activeUser;
      await AccountingService.createCashTransfer(
        fromLocationId: from.id,
        toLocationId: to.id,
        amount: amount,
        notes: notes,
        createdBy: user?.fullName.trim().isNotEmpty == true ? user!.fullName : widget.store.currentRole,
        createdByUserId: user?.id ?? '',
        storeId: widget.store.appIdentity.storeId,
        branchId: widget.store.appIdentity.branchId,
        deviceId: widget.store.appIdentity.deviceId,
        fromSessionId: fromSessionId,
        toSessionId: toSessionId,
        transferKind: kind,
        idempotencyKey: 'cash-ui-$kind-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))));
    }
  }

  Future<void> _openDrawerDialog(
      BuildContext context, List<AdvancedAccountingItem> drawers) async {
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
              items: drawers.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
              onChanged: (value) => setDialogState(() => selectedDrawerId = value ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr.text('opening_amount')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
            FilledButton(onPressed: selectedDrawerId.isEmpty ? null : () => Navigator.pop(dialogContext, true), child: Text(tr.text('open'))),
          ],
        ),
      ),
    );
    if (confirmed != true) { controller.dispose(); return; }
    try {
      final drawer = drawers.firstWhere((item) => item.id == selectedDrawerId);
      final activeUser = widget.store.activeUser;
      await AccountingService.openCashDrawer(
        drawerNo: drawer.name,
        cashLocationId: drawer.id,
        openingBalance: double.tryParse(controller.text.trim()) ?? 0,
        openedBy: activeUser?.fullName.trim().isNotEmpty == true ? activeUser!.fullName : widget.store.currentRole,
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

  Future<void> _closeDrawerDialog(BuildContext context, AdvancedAccountingItem session) async {
    final tr = AppLocalizations.of(context);
    final expected = await AccountingService.calculateCashDrawerExpectedCash(session.id);
    if (!context.mounted) return;
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('close_handover_shift')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${tr.text('expected')}: ${formatUsdReferenceAmount(expected, widget.store.storeProfile)}'),
          const SizedBox(height: 12),
          TextField(controller: counted, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr.text('counted_amount'))),
          const SizedBox(height: 12),
          TextField(controller: notes, decoration: InputDecoration(labelText: tr.text('notes'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr.text('close'))),
        ],
      ),
    );
    if (confirmed != true) { counted.dispose(); notes.dispose(); return; }
    try {
      final activeUser = widget.store.activeUser;
      await AccountingService.closeCashDrawer(
        sessionId: session.id,
        countedCash: double.tryParse(counted.text.trim()) ?? 0,
        closedBy: activeUser?.fullName.trim().isNotEmpty == true ? activeUser!.fullName : widget.store.currentRole,
        closedByUserId: activeUser?.id ?? '',
        notes: notes.text.trim(),
      );
      _refresh();
    } finally {
      counted.dispose();
      notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage = widget.store.canManageAccounting;
    return FutureBuilder<AdvancedAccountingItem?>(
      key: ValueKey('cash_page_$_refreshKey'),
      future: AccountingService.currentCashDrawerForDevice(
        deviceId: _deviceId,
        branchId: _branchId,
      ),
      builder: (context, snapshot) {
        final currentDrawer = snapshot.data;
        return FutureBuilder<List<AdvancedAccountingItem>>(
          future: AccountingService.listOpenCashDrawersReport(),
          builder: (context, sessionsSnapshot) {
            final sessions = sessionsSnapshot.data ?? const <AdvancedAccountingItem>[];
            final currentDrawerSessions = currentDrawer == null
                ? const <AdvancedAccountingItem>[]
                : sessions
                    .where((item) => item.referenceId == currentDrawer.id)
                    .toList(growable: false);
            final currentSession =
                currentDrawerSessions.isEmpty ? null : currentDrawerSessions.first;
            return Padding(
              padding: VentioResponsive.pageInsets(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    CircleAvatar(radius: 18, child: Icon(Icons.point_of_sale_outlined, size: 20, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentDrawer == null
                            ? tr.text('cash_box')
                            : '${tr.text('cash_box')} • ${currentDrawer.name}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _metric(context, tr.text('cash_drawer_sessions'), '${sessions.length}', Icons.point_of_sale_outlined),
                    _metric(context, tr.text('cash_drawer'), currentDrawer == null ? '0' : '1', Icons.account_balance_wallet_outlined),
                  ]),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    FilledButton.icon(
                      onPressed: canManage
                          ? () => _openDrawerDialog(
                              context,
                              currentDrawer == null
                                  ? const <AdvancedAccountingItem>[]
                                  : <AdvancedAccountingItem>[currentDrawer],
                            )
                          : null,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: Text(tr.text('open_shift')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: canManage && currentDrawer != null
                          ? () => _settleSaleInvoiceDialog(currentDrawer)
                          : null,
                      icon: const Icon(Icons.arrow_downward_rounded),
                      label: Text(tr.text('cash_in')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: canManage && currentDrawer != null
                          ? () => _settlePurchaseInvoiceDialog(currentDrawer)
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: Text(tr.text('cash_out')),
                    ),
                    PopupMenuButton<String>(
                      enabled: canManage && currentDrawer != null && currentSession != null,
                      tooltip: _l(tr, 'Cash operations', 'عمليات الصندوق'),
                      onSelected: (value) {
                        if (currentDrawer == null || currentSession == null) return;
                        if (value == 'vault_transfer' || value == 'shift_transfer') {
                          _cashTransferDialog(currentDrawer: currentDrawer, currentSession: currentSession, kind: value);
                        } else {
                          _cashOperationDialog(currentDrawer: currentDrawer, currentSession: currentSession, type: value);
                        }
                      },
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        PopupMenuItem(value: 'cash_deposit', child: Text(_l(tr, 'Cash deposit', 'إيداع نقدي'))),
                        PopupMenuItem(value: 'cash_withdrawal', child: Text(_l(tr, 'Cash withdrawal', 'سحب نقدي'))),
                        PopupMenuItem(value: 'expense', child: Text(_l(tr, 'Cash expense', 'مصروف نقدي'))),
                        const PopupMenuDivider(),
                        PopupMenuItem(value: 'vault_transfer', child: Text(_l(tr, 'Vault transfer', 'تحويل خزنة'))),
                        PopupMenuItem(value: 'shift_transfer', child: Text(_l(tr, 'Shift transfer', 'تحويل شيفت'))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.swap_horiz_rounded),
                          const SizedBox(width: 8),
                          Text(_l(tr, 'Operations', 'العمليات')),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ]),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canManage && currentSession != null
                          ? () => _closeDrawerDialog(context, currentSession)
                          : null,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(tr.text('close')),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (currentDrawer == null)
                    Expanded(
                      child: Card(
                        elevation: 0,
                        child: Center(child: Text(tr.text('no_cash_drawer_for_device'))),
                      ),
                    )
                  else ...[
                    if (currentSession != null)
                      Card(
                        elevation: 0,
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.point_of_sale_outlined)),
                          title: Text(currentSession.name),
                          subtitle: Text([
                            tr.text('drawer_linked_to_device_found'),
                            if (currentSession.accountName.isNotEmpty) currentSession.accountName,
                            if (currentSession.notes.trim().isNotEmpty) currentSession.notes,
                          ].join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: canManage
                              ? TextButton(
                                  onPressed: () => _closeDrawerDialog(context, currentSession),
                                  child: Text(tr.text('close')),
                                )
                              : null,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          tr.text('no_open_cash_shift'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Expanded(
                      child: CashHistoryPanel(
                        store: widget.store,
                        cashLocationId: currentDrawer.id,
                        currentSessionId: currentSession?.id ?? '',
                        refreshKey: _refreshKey,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _metric(BuildContext context, String label, String value, IconData icon) {
    return SizedBox(
      width: VentioResponsive.adaptiveWidth(context, mobile: 180, tablet: 210, desktop: 240),
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(child: Icon(icon, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
      ),
    );
  }
}
