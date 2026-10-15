// ignore_for_file: invalid_use_of_protected_member
part of 'cash_page.dart';

extension _CashPageStatePart1 on _CashPageState {
  void _refresh() {
    if (mounted) setState(() => _refreshKey++);
  }

  String get _deviceId => widget.store.appIdentity.deviceId.trim();
  String get _branchId => widget.store.appIdentity.branchId.trim();

  Future<List<Purchase>> _cashPurchasesSnapshot() async {
    final sqlitePurchases = await LocalDatabaseService.getPurchasesFromSqlite();
    return (sqlitePurchases ?? widget.store.purchases)
        .where((purchase) => !purchase.isDeleted)
        .toList(growable: false);
  }

  Future<void> _settleSaleInvoiceDialog(
      AdvancedAccountingItem currentDrawer) async {
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
    final amountController =
        TextEditingController(text: selectedSale.balanceDue.toStringAsFixed(2));
    final discountController = TextEditingController(text: '0.00');
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
                            child: Text(
                                '${sale.invoiceNo} • ${sale.customerName} • ${formatUsdReferenceAmount(sale.balanceDue, widget.store.storeProfile)}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    final found =
                        openSales.where((sale) => sale.id == value).toList();
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selectedSale = found.first;
                      amountController.text =
                          selectedSale.balanceDue.toStringAsFixed(2);
                      discountController.text = '0.00';
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('CashReceiptAmountField'),
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: tr.text('amount'),
                          helperText:
                              '${tr.text('remaining_debt')}: ${formatUsdReferenceAmount(selectedSale.balanceDue, widget.store.storeProfile)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('CashReceiptDiscountField'),
                        controller: discountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: tr.text('discount'),
                        ),
                      ),
                    ),
                  ],
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
      discountController.dispose();
      notesController.dispose();
      return;
    }
    if (!mounted) {
      amountController.dispose();
      discountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final discount = double.tryParse(discountController.text.trim()) ?? 0;
    if (amount < 0 ||
        discount < 0 ||
        amount + discount <= 0 ||
        amount + discount > selectedSale.balanceDue + 0.0001) {
      amountController.dispose();
      discountController.dispose();
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
        discount: discount,
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
      discountController.dispose();
      notesController.dispose();
    }
    _refresh();
  }

  Future<void> _settlePurchaseInvoiceDialog(
      AdvancedAccountingItem currentDrawer) async {
    final tr = AppLocalizations.of(context);
    final purchases = await _cashPurchasesSnapshot();
    if (!mounted) return;
    final openPurchases = purchases
        .where((purchase) =>
            !purchase.isCancelled &&
            !purchase.isPurchaseReturn &&
            purchase.balanceDue > 0 &&
            purchase.isReceived)
        .toList(growable: false);
    if (openPurchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_purchases'))),
      );
      return;
    }
    Purchase selectedPurchase = openPurchases.first;
    final amountController = TextEditingController(
        text: selectedPurchase.balanceDue.toStringAsFixed(2));
    final discountController = TextEditingController(text: '0.00');
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
                            child: Text(
                                '${purchase.purchaseNo} • ${purchase.supplierName} • ${formatUsdReferenceAmount(purchase.balanceDue, widget.store.storeProfile)}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    final found = openPurchases
                        .where((purchase) => purchase.id == value)
                        .toList();
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selectedPurchase = found.first;
                      amountController.text =
                          selectedPurchase.balanceDue.toStringAsFixed(2);
                      discountController.text = '0.00';
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('CashPaymentAmountField'),
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: tr.text('amount'),
                          helperText:
                              '${tr.text('remaining_debt')}: ${formatUsdReferenceAmount(selectedPurchase.balanceDue, widget.store.storeProfile)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('CashPaymentDiscountField'),
                        controller: discountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: tr.text('discount'),
                        ),
                      ),
                    ),
                  ],
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
      discountController.dispose();
      notesController.dispose();
      return;
    }
    if (!mounted) {
      amountController.dispose();
      discountController.dispose();
      notesController.dispose();
      return;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final discount = double.tryParse(discountController.text.trim()) ?? 0;
    if (amount < 0 ||
        discount < 0 ||
        amount + discount <= 0 ||
        amount + discount > selectedPurchase.balanceDue + 0.0001) {
      amountController.dispose();
      discountController.dispose();
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
        discount: discount,
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
      discountController.dispose();
      notesController.dispose();
    }
    _refresh();
  }

  String _l(AppLocalizations tr, String en, String ar) => tr.isArabic ? ar : en;

  Future<void> _refundPurchaseReturnDialog() async {
    final tr = AppLocalizations.of(context);
    await widget.store.ensurePurchasesPageDataLoaded();
    if (!mounted) return;
    final purchases = await _cashPurchasesSnapshot();
    if (!mounted) return;
    final returns = <Map<String, Object>>[];
    for (final purchase in purchases.where((item) =>
        !item.isDeleted && !item.isCancelled && item.isPurchaseReturn)) {
      try {
        final available =
            await widget.store.refundablePurchaseReturnCashAmount(purchase.id);
        if (available > 0.000001) {
          returns.add(<String, Object>{
            'purchase': purchase,
            'amount': available,
          });
        }
      } catch (_) {
        // A single stale return must not hide other eligible refunds.
      }
    }
    if (!mounted) return;
    if (returns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l(
            tr,
            'No purchase return has a cash amount available for refund.',
            'لا يوجد مرتجع شراء لديه مبلغ نقدي متاح للاسترداد.',
          )),
        ),
      );
      return;
    }
    var selected = returns.first;
    final amountController = TextEditingController(
      text: (selected['amount'] as double).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final purchase = selected['purchase'] as Purchase;
          final available = selected['amount'] as double;
          return AlertDialog(
            title: Text(_l(
              tr,
              'Purchase return refund',
              'استرداد مرتجع شراء',
            )),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: purchase.id,
                    decoration: InputDecoration(
                      labelText: _l(tr, 'Purchase return', 'مرتجع الشراء'),
                    ),
                    items: returns.map((item) {
                      final itemPurchase = item['purchase'] as Purchase;
                      final itemAmount = item['amount'] as double;
                      return DropdownMenuItem<String>(
                        value: itemPurchase.id,
                        child: Text(
                          '${itemPurchase.purchaseNo} • ${itemPurchase.supplierName} • ${formatUsdReferenceAmount(itemAmount, widget.store.storeProfile)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      final found = returns.where(
                        (item) => (item['purchase'] as Purchase).id == value,
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
                          '${_l(tr, 'Available', 'المتاح')}: ${formatUsdReferenceAmount(available, widget.store.storeProfile)}',
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
                child: Text(_l(tr, 'Post refund', 'تسجيل الاسترداد')),
              ),
            ],
          );
        },
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
    final normalizedAmount = amountController.text
        .trim()
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(normalizedAmount) ?? 0;
    final available = selected['amount'] as double;
    if (amount <= 0 || amount > available + 0.005001) {
      amountController.dispose();
      notesController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('invalid_paid_amount'))),
      );
      return;
    }
    try {
      final purchase = selected['purchase'] as Purchase;
      final refunded = await widget.store.refundPurchaseReturnCash(
        purchaseReturnId: purchase.id,
        amount: amount,
        notes: notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_l(tr, 'Refund posted', 'تم تسجيل الاسترداد')}: ${formatUsdReferenceAmount(refunded, widget.store.storeProfile)}',
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
}
