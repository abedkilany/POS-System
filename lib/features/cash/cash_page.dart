import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/services/accounting_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';

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
      final newPaid = (selectedSale.paidAmount + amount).clamp(0, selectedSale.invoiceTotal).toDouble();
      final updatedStatus = newPaid >= selectedSale.invoiceTotal - 0.0001 ? 'paid' : 'partial';
      await widget.store.editSale(
        id: selectedSale.id,
        customerName: selectedSale.customerName,
        customerId: selectedSale.customerId,
        items: selectedSale.items,
        discount: selectedSale.discount,
        paymentMethod: 'Cash',
        paymentStatus: updatedStatus,
        paidAmount: newPaid,
        cashReceivedAmount: (selectedSale.cashReceivedAmount + amount).clamp(0, selectedSale.invoiceTotal).toDouble(),
        note: notesController.text.trim().isEmpty ? selectedSale.note : notesController.text.trim(),
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
      final newPaid = (selectedPurchase.paidAmount + amount).clamp(0, selectedPurchase.subtotal).toDouble();
      final updatedStatus = newPaid >= selectedPurchase.subtotal - 0.0001 ? 'paid' : 'partial';
      await widget.store.editReceivedPurchase(
        id: selectedPurchase.id,
        supplierId: selectedPurchase.supplierId,
        supplierName: selectedPurchase.supplierName,
        items: selectedPurchase.items,
        paymentStatus: updatedStatus,
        paymentMethod: 'Cash',
        paidAmount: newPaid,
        note: notesController.text.trim().isEmpty ? selectedPurchase.note : notesController.text.trim(),
        warehouseId: selectedPurchase.warehouseId,
        warehouseName: selectedPurchase.warehouseName,
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

  Future<void> _cashMoveDialog(
    BuildContext context, {
    required AdvancedAccountingItem currentDrawer,
    required bool isReceipt,
  }) async {
    final tr = AppLocalizations.of(context);
    final locations = await AccountingService.listActiveCashLocations();
    final counterparty = locations
        .where((item) => item.id != currentDrawer.id)
        .toList(growable: false);
    if (counterparty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_cash_locations'))),
      );
      return;
    }
    final amount = TextEditingController(text: '0');
    final notes = TextEditingController();
    String selectedLocationId = counterparty.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(isReceipt ? tr.text('cash_in') : tr.text('cash_out')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedLocationId,
                  decoration: InputDecoration(
                    labelText: isReceipt
                        ? tr.text('from_cash_location')
                        : tr.text('to_cash_location'),
                  ),
                  items: counterparty
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedLocationId = value ?? ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr.text('amount')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
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
              onPressed: selectedLocationId.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('post')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      amount.dispose();
      notes.dispose();
      return;
    }
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (value <= 0) {
      amount.dispose();
      notes.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('positive_amount_required'))),
      );
      return;
    }
    try {
      final user = widget.store.activeUser;
      final actor = user?.fullName.trim().isNotEmpty == true
          ? user!.fullName.trim()
          : widget.store.currentRole;
      await AccountingService.createCashTransfer(
        fromLocationId:
            isReceipt ? selectedLocationId : currentDrawer.id,
        toLocationId:
            isReceipt ? currentDrawer.id : selectedLocationId,
        amount: value,
        notes: notes.text.trim().isEmpty
            ? (isReceipt ? tr.text('cash_in') : tr.text('cash_out'))
            : notes.text.trim(),
        createdBy: actor,
        storeId: widget.store.appIdentity.storeId,
        branchId: _branchId,
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      amount.dispose();
      notes.dispose();
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
      if (!mounted) return;
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
    if (!mounted) return;
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
                  Row(children: [
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
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: canManage && currentSession != null
                          ? () => _closeDrawerDialog(context, currentSession!)
                          : null,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(tr.text('close')),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      elevation: 0,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: currentDrawer == null
                            ? 1
                            : (currentDrawerSessions.isEmpty ? 1 : currentDrawerSessions.length),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (currentDrawer == null) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(tr.text('no_cash_drawer_for_device')),
                              ),
                            );
                          }
                          if (currentDrawerSessions.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(tr.text('no_open_cash_shift')),
                              ),
                            );
                          }
                          final session = currentDrawerSessions[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.point_of_sale_outlined)),
                            title: Text(session.name),
                            subtitle: Text([
                              if (session.referenceId == currentDrawer.id) tr.text('drawer_linked_to_device_found'),
                              if (session.accountName.isNotEmpty) session.accountName,
                              if (session.referenceId.isNotEmpty) session.referenceId,
                              if (session.notes.trim().isNotEmpty) session.notes
                            ].join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: canManage ? TextButton(onPressed: () => _closeDrawerDialog(context, session), child: Text(tr.text('close'))) : null,
                          );
                        },
                      ),
                    ),
                  ),
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
