import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/cash_operation_service.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/cash_shift_report_pdf_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/accounting_account.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/expense.dart';
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

  Future<void> _refundDialog() async {
    final tr = AppLocalizations.of(context);
    final options = <Map<String, Object>>[];

    if (widget.store.canDeleteOrCancel) {
      for (final sale in widget.store.sales.where(
        (item) => !item.isDeleted && (item.isCancelled || item.returnedAmount > 0),
      )) {
        try {
          final available = await widget.store.refundableSaleCashAmount(sale.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'sale',
              'id': sale.id,
              'label': '${sale.invoiceNo} • ${sale.customerName}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale invoice must not prevent other valid refunds.
        }
      }
    }

    if (widget.store.canManageSuppliers) {
      for (final purchase in widget.store.purchases.where(
        (item) => !item.isDeleted && item.isCancelled,
      )) {
        try {
          final available =
              await widget.store.refundablePurchaseCashAmount(purchase.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'purchase',
              'id': purchase.id,
              'label': '${purchase.purchaseNo} • ${purchase.supplierName}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale invoice must not prevent other valid refunds.
        }
      }
    }

    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l(
            tr,
            'No returned invoice has a cash amount available for refund.',
            'لا توجد فاتورة مرتجعة لديها مبلغ نقدي متاح للاسترداد.',
          )),
        ),
      );
      return;
    }

    var selected = options.first;
    final amountController = TextEditingController(
      text: (selected['amount'] as double).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_l(tr, 'Refund', 'استرداد')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: '${selected['kind']}:${selected['id']}',
                  decoration: InputDecoration(
                    labelText: _l(tr, 'Returned invoice', 'الفاتورة المرتجعة'),
                  ),
                  items: options.map((item) {
                    final kind = item['kind'] as String;
                    final direction = kind == 'purchase'
                        ? _l(tr, 'Supplier → Cash', 'من المورد إلى الصندوق')
                        : _l(tr, 'Cash → Customer', 'من الصندوق إلى الزبون');
                    return DropdownMenuItem<String>(
                      value: '$kind:${item['id']}',
                      child: Text(
                        '$direction • ${item['label']} • ${formatUsdReferenceAmount(item['amount'] as double, widget.store.storeProfile)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    final found = options.where(
                      (item) => '${item['kind']}:${item['id']}' == value,
                    );
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selected = found.first;
                      amountController.text =
                          (selected['amount'] as double).toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr.text('amount'),
                    helperText:
                        '${_l(tr, 'Available', 'المتاح')}: ${formatUsdReferenceAmount(selected['amount'] as double, widget.store.storeProfile)}',
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
              child: Text(_l(tr, 'Refund', 'استرداد')),
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

    final rawAmount = amountController.text.trim();
    final normalizedAmount = rawAmount
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(normalizedAmount) ?? 0;
    final available = selected['amount'] as double;
    // The dialog displays/refills monetary amounts to 2 decimals while the
    // accounting layer intentionally keeps up to 6 decimals. Accept a value
    // that differs only by normal cent-rounding; the service below still caps
    // the posted refund to the exact authoritative refundable amount.
    const displayRoundingTolerance = 0.005001;
    if (amount <= 0 || amount > available + displayRoundingTolerance) {
      amountController.dispose();
      notesController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l(tr, 'Invalid refund amount.', 'قيمة الاسترداد غير صالحة.')),
        ),
      );
      return;
    }

    try {
      final kind = selected['kind'] as String;
      final id = selected['id'] as String;
      final refunded = kind == 'purchase'
          ? await widget.store.refundPurchaseCash(
              purchaseId: id,
              amount: amount,
              notes: notesController.text.trim(),
            )
          : await widget.store.refundSaleCash(
              saleId: id,
              amount: amount,
              notes: notesController.text.trim(),
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refunded > 0
                ? '${_l(tr, 'Refund posted', 'تم تسجيل الاسترداد')}: ${formatUsdReferenceAmount(refunded, widget.store.storeProfile)}'
                : _l(tr, 'Nothing remains to refund.', 'لا يوجد مبلغ متبقٍ للاسترداد.'),
          ),
        ),
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


  Future<void> _settleExpenseDialog(
    AdvancedAccountingItem? currentDrawer,
    AdvancedAccountingItem? currentSession,
  ) async {
    final tr = AppLocalizations.of(context);

    // The cash-page Expenses action is reserved for expenses that were already
    // approved as credit. Draft expenses must stay in the Expenses module until
    // they are approved, and cash-approved expenses have already affected cash.
    final creditExpenseIds =
        await AccountingService.readOutstandingCreditExpenseIds();
    if (!mounted) return;
    final creditExpenses = widget.store.expenses
        .where((expense) =>
            !expense.isDeleted &&
            expense.isPosted &&
            expense.amount > 0 &&
            creditExpenseIds.contains(expense.id.trim()))
        .toList(growable: false);
    if (creditExpenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              tr,
              'No approved credit expenses are available for disbursement.',
              'لا توجد مصاريف معتمدة آجلة متاحة للصرف.',
            ),
          ),
        ),
      );
      return;
    }

    Expense selectedExpense = creditExpenses.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_l(tr, 'Expense disbursement', 'صرف مصروف')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedExpense.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _l(tr, 'Expense', 'المصروف'),
                  ),
                  items: creditExpenses
                      .map(
                        (expense) => DropdownMenuItem<String>(
                          value: expense.id,
                          child: Text(
                            '${expense.title} • ${expense.category} • ${formatUsdReferenceAmount(expense.amount, widget.store.storeProfile)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    final found = creditExpenses
                        .where((expense) => expense.id == value)
                        .toList(growable: false);
                    if (found.isEmpty) return;
                    setDialogState(() => selectedExpense = found.first);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${tr.text('amount')}: ${formatUsdReferenceAmount(selectedExpense.amount, widget.store.storeProfile)}',
                  ),
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
              child: Text(_l(tr, 'Disburse', 'صرف')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (currentDrawer == null || currentSession == null) {
        throw StateError(
          _l(tr, 'An open cash shift is required.', 'يجب وجود وردية صندوق مفتوحة.'),
        );
      }
      final defaults = await AccountingService.readDefaultAccountMap();
      final payableAccountId =
          (defaults['default_suppliers_account_id'] ?? '').trim();
      if (payableAccountId.isEmpty) {
        throw StateError(
          _l(
            tr,
            'The default payables account is not configured.',
            'حساب الذمم الدائنة الافتراضي غير مضبوط.',
          ),
        );
      }
      final user = widget.store.activeUser;
      await CashOperationService.current().withdrawal(
        cashLocationId: currentDrawer.id,
        cashDrawerSessionId: currentSession.id,
        counterpartAccountId: payableAccountId,
        amount: selectedExpense.amount,
        notes: 'Expense credit settlement: ${selectedExpense.id} - ${selectedExpense.title}',
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName
            : widget.store.currentRole,
        createdByUserId: user?.id ?? '',
        deviceId: widget.store.appIdentity.deviceId,
        branchId: widget.store.appIdentity.branchId,
        storeId: widget.store.appIdentity.storeId,
        idempotencyKey: 'expense-credit-settlement:${selectedExpense.id}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              tr,
              'Credit expense settled successfully.',
              'تم صرف المصروف الآجل وتسجيل حركة الصندوق بنجاح.',
            ),
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    }
  }

  Future<void> _cashOperationDialog({
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem currentSession,
    required String type,
  }) async {
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
      childrenByParent.putIfAbsent(parentId, () => <AccountingAccount>[]).add(account);
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
        pending.addAll(childrenByParent[account.id] ?? const <AccountingAccount>[]);
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
                child: Text('${_l(tr, 'Cash location', 'موقع النقدية')}: ${currentDrawer.name}'),
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
                    : (value) => setDialogState(() => selectedCounterpart = value),
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
          SnackBar(content: Text(_l(tr, 'Enter a valid amount.', 'أدخل مبلغاً صالحاً.'))),
        );
      }
      return;
    }
    try {
      final user = widget.store.activeUser;
      final service = CashOperationService.current();
      final args = (
        cashLocationId: currentDrawer.id,
        cashDrawerSessionId: currentSession.id,
        counterpartAccountId: counterpartAccountId,
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

  Future<List<CashLedgerTransaction>> _loadAllShiftMovements(String sessionId) async {
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

  Future<void> _showShiftReportsDialog() async {
    final tr = AppLocalizations.of(context);
    var detailed = false;
    var printingSessionId = '';
    final sessionsFuture = AccountingService.listClosedCashDrawerSessions(limit: 500);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.summarize_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(_l(tr, 'Closed shift reports', 'تقارير الورديات المغلقة'))),
            ],
          ),
          content: SizedBox(
            width: 900,
            height: 560,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(detailed
                      ? _l(tr, 'Detailed report', 'تقرير مفصل')
                      : _l(tr, 'Summary report', 'تقرير ملخص')),
                  subtitle: Text(_l(
                    tr,
                    detailed
                        ? 'Printing includes every cash movement linked to the selected shift.'
                        : 'Printing includes the closing summary for the selected shift only.',
                    detailed
                        ? 'الطباعة تشمل جميع حركات الصندوق المرتبطة بالوردية المختارة.'
                        : 'الطباعة تشمل ملخص إغلاق الوردية المختارة فقط.',
                  )),
                  value: detailed,
                  onChanged: (value) => setDialogState(() => detailed = value),
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<CashShiftReportSession>>(
                    future: sessionsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text(localizeRuntimeMessage(snapshot.error.toString(), tr)));
                      }
                      final sessions = snapshot.data ?? const <CashShiftReportSession>[];
                      if (sessions.isEmpty) {
                        return Center(child: Text(_l(tr, 'No closed shifts found.', 'لا توجد ورديات مغلقة.')));
                      }
                      return ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          String date(DateTime? value) {
                            if (value == null) return '—';
                            final d = value.toLocal();
                            String two(int n) => n.toString().padLeft(2, '0');
                            return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
                          }
                          final isPrinting = printingSessionId == session.id;
                          return ListTile(
                            leading: const Icon(Icons.lock_outline_rounded),
                            title: Text(
                              '${session.drawerNo.isEmpty ? session.id : session.drawerNo} • ${session.cashLocationName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_l(tr, 'Closed', 'أغلقت')}: ${date(session.closedAt)} • '
                              '${_l(tr, 'Expected', 'المتوقع')}: ${formatUsdReferenceAmount(session.expectedCash, widget.store.storeProfile)} • '
                              '${_l(tr, 'Counted', 'المعدود')}: ${formatUsdReferenceAmount(session.countedCash, widget.store.storeProfile)} • '
                              '${_l(tr, 'Difference', 'الفرق')}: ${formatUsdReferenceAmount(session.difference, widget.store.storeProfile)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: isPrinting ? null : () async {
                                final printDetailed = detailed;
                                setDialogState(() => printingSessionId = session.id);
                                try {
                                  final movements = await _loadAllShiftMovements(session.id);
                                  if (!dialogContext.mounted) return;
                                  await CashShiftReportPdfService.printShift(
                                    session: session,
                                    movements: movements,
                                    detailed: printDetailed,
                                    profile: widget.store.storeProfile,
                                    locale: Localizations.localeOf(dialogContext),
                                  );
                                } catch (error) {
                                  if (dialogContext.mounted) {
                                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                                      SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
                                    );
                                  }
                                } finally {
                                  if (dialogContext.mounted) {
                                    setDialogState(() => printingSessionId = '');
                                  }
                                }
                              },
                              icon: isPrinting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.print_outlined),
                              label: Text(_l(tr, 'Print', 'طباعة')),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('close')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage = widget.store.canManageCashBox;
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
            String money(double value) =>
                formatUsdReferenceAmount(value, widget.store.storeProfile);
            final openingBalance = (currentSession?.debit ?? 0).toDouble();
            final expectedBalance =
                (currentSession?.credit ?? currentDrawer?.balance ?? 0).toDouble();
            final shiftNet = currentSession == null
                ? 0.0
                : expectedBalance - openingBalance;

            return Padding(
              padding: VentioResponsive.pageInsets(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pageHeader(context, tr, currentDrawer, currentSession),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 900;
                      final itemWidth = compact
                          ? (constraints.maxWidth - 10) / 2
                          : (constraints.maxWidth - 30) / 4;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Current balance', 'الرصيد الحالي'),
                            value: currentDrawer == null ? '—' : money(currentDrawer.balance),
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Opening balance', 'رصيد الافتتاح'),
                            value: currentSession == null ? '—' : money(openingBalance),
                            icon: Icons.login_rounded,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Expected balance', 'الرصيد المتوقع'),
                            value: currentSession == null ? '—' : money(expectedBalance),
                            icon: Icons.calculate_outlined,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Shift net', 'صافي الوردية'),
                            value: currentSession == null ? '—' : money(shiftNet),
                            icon: Icons.balance_outlined,
                            emphasize: true,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _quickActionsCard(
                    context,
                    tr,
                    canManage: canManage,
                    currentDrawer: currentDrawer,
                    currentSession: currentSession,
                  ),
                  const SizedBox(height: 14),
                  if (currentDrawer == null)
                    Expanded(
                      child: Card(
                        elevation: 0,
                        child: Center(child: Text(tr.text('no_cash_drawer_for_device'))),
                      ),
                    )
                  else
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 1050) {
                            return Column(
                              children: [
                                _shiftSummaryCard(
                                  context,
                                  tr,
                                  currentDrawer: currentDrawer,
                                  currentSession: currentSession,
                                  canManage: canManage,
                                  compact: true,
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: CashHistoryPanel(
                                    store: widget.store,
                                    cashLocationId: currentDrawer.id,
                                    currentSessionId: currentSession?.id ?? '',
                                    refreshKey: _refreshKey,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 315,
                                child: _shiftSummaryCard(
                                  context,
                                  tr,
                                  currentDrawer: currentDrawer,
                                  currentSession: currentSession,
                                  canManage: canManage,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: CashHistoryPanel(
                                  store: widget.store,
                                  cashLocationId: currentDrawer.id,
                                  currentSessionId: currentSession?.id ?? '',
                                  refreshKey: _refreshKey,
                                ),
                              ),
                            ],
                          );
                        },
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

  Widget _pageHeader(
    BuildContext context,
    AppLocalizations tr,
    AdvancedAccountingItem? currentDrawer,
    AdvancedAccountingItem? currentSession,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.point_of_sale_outlined, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentDrawer == null
                    ? tr.text('cash_box')
                    : '${tr.text('cash_box')} • ${currentDrawer.name}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                currentSession == null
                    ? _l(tr, 'No open shift', 'لا توجد وردية مفتوحة')
                    : _l(tr, 'Open shift • live cash overview', 'وردية مفتوحة • ملخص النقد المباشر'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _showShiftReportsDialog,
          icon: const Icon(Icons.summarize_outlined),
          label: Text(_l(tr, 'Reports', 'تقارير')),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: _l(tr, 'Refresh', 'تحديث'),
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _dashboardMetric(
    BuildContext context, {
    required double width,
    required String label,
    required String value,
    required IconData icon,
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: emphasize ? 0.10 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionsCard(
    BuildContext context,
    AppLocalizations tr, {
    required bool canManage,
    required AdvancedAccountingItem? currentDrawer,
    required AdvancedAccountingItem? currentSession,
  }) {
    final enabled = canManage && currentDrawer != null && currentSession != null;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _l(tr, 'Quick actions', 'عمليات سريعة'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (currentSession == null)
                  FilledButton.icon(
                    onPressed: canManage && currentDrawer != null
                        ? () => _openDrawerDialog(
                              context,
                              <AdvancedAccountingItem>[currentDrawer],
                            )
                        : null,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(tr.text('open_shift')),
                  ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.canEditSales
                      ? () => _settleSaleInvoiceDialog(currentDrawer)
                      : null,
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: Text(_l(tr, 'Receipt', 'قبض')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.canManageSuppliers
                      ? () => _settlePurchaseInvoiceDialog(currentDrawer)
                      : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(_l(tr, 'Payment', 'دفع')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled &&
                          (widget.store.canDeleteOrCancel ||
                              widget.store.canManageSuppliers)
                      ? _refundDialog
                      : null,
                  icon: const Icon(Icons.currency_exchange_rounded),
                  label: Text(_l(tr, 'Refund', 'استرداد')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.canManageExpenses
                      ? () => _settleExpenseDialog(currentDrawer, currentSession)
                      : null,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(_l(tr, 'Expenses', 'مصاريف')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled
                      ? () => _cashTransferDialog(
                            currentDrawer: currentDrawer,
                            currentSession: currentSession,
                            kind: 'vault_transfer',
                          )
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(_l(tr, 'Transfer', 'تحويل')),
                ),
                PopupMenuButton<String>(
                  enabled: enabled,
                  tooltip: _l(tr, 'More cash operations', 'عمليات نقدية إضافية'),
                  onSelected: (value) {
                    if (currentDrawer == null || currentSession == null) return;
                    if (value == 'vault_transfer' || value == 'shift_transfer') {
                      _cashTransferDialog(
                        currentDrawer: currentDrawer,
                        currentSession: currentSession,
                        kind: value,
                      );
                    } else {
                      _cashOperationDialog(
                        currentDrawer: currentDrawer,
                        currentSession: currentSession,
                        type: value,
                      );
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'cash_deposit',
                      child: Text(_l(tr, 'Cash deposit', 'إيداع نقدي')),
                    ),
                    PopupMenuItem(
                      value: 'cash_withdrawal',
                      child: Text(_l(tr, 'Cash withdrawal', 'سحب نقدي')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'vault_transfer',
                      child: Text(_l(tr, 'Vault transfer', 'تحويل خزنة')),
                    ),
                    PopupMenuItem(
                      value: 'shift_transfer',
                      child: Text(_l(tr, 'Shift transfer', 'تحويل شيفت')),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.more_horiz_rounded, size: 20),
                        const SizedBox(width: 6),
                        Text(_l(tr, 'More', 'المزيد')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftSummaryCard(
    BuildContext context,
    AppLocalizations tr, {
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem? currentSession,
    required bool canManage,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String money(double value) =>
        formatUsdReferenceAmount(value, widget.store.storeProfile);
    if (currentSession == null) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_clock_outlined,
                  size: 34, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                tr.text('no_open_cash_shift'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canManage
                    ? () => _openDrawerDialog(
                          context,
                          <AdvancedAccountingItem>[currentDrawer],
                        )
                    : null,
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(tr.text('open_shift')),
              ),
            ],
          ),
        ),
      );
    }

    final opening = currentSession.debit;
    final expected = currentSession.credit;
    final actual = currentDrawer.balance;
    final shiftNet = expected - opening;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _l(tr, 'Shift summary', 'ملخص الوردية'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _l(tr, 'Open', 'مفتوحة'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _shiftLine(context, _l(tr, 'Opening balance', 'رصيد الافتتاح'), money(opening)),
            _shiftLine(context, _l(tr, 'Shift net', 'صافي الوردية'), money(shiftNet)),
            _shiftLine(context, _l(tr, 'Expected balance', 'الرصيد المتوقع'), money(expected)),
            _shiftLine(context, _l(tr, 'Current balance', 'الرصيد الحالي'), money(actual), strong: true),
            if (!compact) const Spacer(),
            if (currentSession.notes.trim().isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                currentSession.notes,
                maxLines: compact ? 1 : 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canManage
                  ? () => _closeDrawerDialog(context, currentSession)
                  : null,
              icon: const Icon(Icons.lock_outline),
              label: Text(_l(tr, 'Close shift', 'إغلاق الوردية')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftLine(
    BuildContext context,
    String label,
    String value, {
    bool strong = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

}
