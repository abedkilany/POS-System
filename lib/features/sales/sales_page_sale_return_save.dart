// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageSaleReturnSave on _SalesPageState {
  Future<void> _editLatestSaleReturn(
      BuildContext sheetContext, Sale sale) async {
    if (!widget.store.security.hasPermission(AppPermission.salesEdit) ||
        !widget.store.security.hasPermission(AppPermission.salesCancel)) {
      return;
    }
    await widget.store.commerce.ensureCreditNotesLoaded();
    final note = _latestActiveCreditNoteForSale(sale.id);
    if (note == null || !sheetContext.mounted) return;
    final tr = AppLocalizations.of(sheetContext);
    final otherReturned = <String, double>{};
    for (final candidate in widget.store.commerce.creditNotes) {
      if (candidate.originalSaleId != sale.id || candidate.id == note.id) {
        continue;
      }
      if (<String>{'cancelled', 'reversed', 'void'}
          .contains(candidate.status.trim().toLowerCase())) {
        continue;
      }
      for (final item in candidate.items) {
        otherReturned.update(item.productId, (value) => value + item.quantity,
            ifAbsent: () => item.quantity);
      }
    }
    final originalByProduct = <String, double>{};
    final productNameById = <String, String>{};
    for (final item in sale.items) {
      originalByProduct.update(item.productId, (value) => value + item.quantity,
          ifAbsent: () => item.quantity);
      productNameById[item.productId] = item.productName;
    }
    final currentByProduct = <String, double>{};
    for (final item in note.items) {
      currentByProduct.update(item.productId, (value) => value + item.quantity,
          ifAbsent: () => item.quantity);
    }
    final controllers = <String, TextEditingController>{
      for (final productId in originalByProduct.keys)
        productId: TextEditingController(
            text: (currentByProduct[productId] ?? 0).toString())
    };
    Map<String, double>? editedQuantities;
    try {
      editedQuantities = await showDialog<Map<String, double>>(
          context: sheetContext,
          builder: (dialogContext) => AlertDialog(
                  title: Text('${tr.text('edit')} • ${_saleReturnLabel(tr)}'),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${note.creditNoteNo} • v${note.version}'),
                        const SizedBox(height: 12),
                        for (final entry in originalByProduct.entries) ...[
                          TextField(
                              controller: controllers[entry.key],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText:
                                      productNameById[entry.key] ?? entry.key,
                                  helperText:
                                      '${tr.text('quantity')}: 0 - ${(entry.value - (otherReturned[entry.key] ?? 0)).clamp(0, double.infinity)}')),
                          const SizedBox(height: 10)
                        ]
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(tr.text('cancel'))),
                    FilledButton.icon(
                        onPressed: () {
                          final values = <String, double>{};
                          for (final entry in controllers.entries) {
                            final value =
                                double.tryParse(entry.value.text.trim()) ?? -1;
                            final max = (originalByProduct[entry.key]! -
                                    (otherReturned[entry.key] ?? 0))
                                .clamp(0, double.infinity)
                                .toDouble();
                            if (value < 0 || value > max + 0.000001) return;
                            if (value > 0.000001) values[entry.key] = value;
                          }
                          if (values.isEmpty) return;
                          Navigator.pop(dialogContext, values);
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(tr.text('save')))
                  ]));
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    if (editedQuantities == null || !sheetContext.mounted) return;
    if (!await requestSensitiveActionAuthorization(sheetContext, widget.store,
        action: SensitiveAction.saleReverse)) {
      return;
    }
    try {
      await widget.store.commerce.editSaleReturn(
          creditNoteId: note.id,
          expectedVersion: note.version,
          returnedQuantities: editedQuantities);
      if (!mounted) return;
      setState(() {
        _salesQueryFuture = null;
        _salesQueryFutureKey = '';
        _invoiceDetailsFutureById.clear();
        _invoiceSearchIndexCache.invalidate();
      });
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
            content: Text('${_saleReturnLabel(tr)} • ${tr.text('saved')}')));
      }
    } catch (error) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext)
          .showSnackBar(SnackBar(content: Text(localizedErrorText(tr, error))));
    }
  }

  Future<void> _returnSale(BuildContext sheetContext, Sale sale) async {
    if (!widget.store.security.hasPermission(AppPermission.salesCancel) ||
        sale.isCancelled) {
      return;
    }
    final tr = AppLocalizations.of(sheetContext);
    final confirmed = await showDialog<bool>(
        context: sheetContext,
        builder: (dialogContext) => AlertDialog(
                title: Text(_saleReturnLabel(tr)),
                content: Text(tr.format(
                    'invoice_return_confirm', {'invoice': sale.invoiceNo})),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(tr.text('cancel'))),
                  FilledButton(
                      key: const ValueKey('SalesReturnConfirmButton'),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(tr.text('confirm')))
                ]));
    if (confirmed != true) return;
    if (!sheetContext.mounted) return;
    if (!await requestSensitiveActionAuthorization(sheetContext, widget.store,
        action: SensitiveAction.saleReverse)) {
      return;
    }
    try {
      await widget.store.commerce.returnSale(sale.id, restoreStock: true);
      if (!mounted) return;
      setState(() {
        _salesQueryFuture = null;
        _salesQueryFutureKey = '';
        _invoiceDetailsFutureById.clear();
        _invoiceSearchIndexCache.invalidate();
      });
      if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
        Navigator.of(sheetContext).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('invoice_return_created'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(localizedErrorText(tr, error))));
    }
  }

  Future<bool> _confirmInvoicePrintAfterSave() async {
    final tr = AppLocalizations.of(context);
    final shouldPrint = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                Navigator.of(dialogContext).pop(true);
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(dialogContext).pop(false);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AlertDialog(
                title: Text(tr.text('print_invoice_after_save_question')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(tr.text('no'))),
                  FilledButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(tr.text('yes')))
                ])));
    return shouldPrint == true;
  }

  Future<void> _saveCurrentInvoice() async {
    if (_cart.isEmpty) return;
    if (_discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('discount_exceeds_subtotal'))));
      return;
    }
    if (_isWalkInCustomer && _paymentMethod == 'Credit') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('walk_in_cash_only'))));
      return;
    }
    final cashReceivedAmount = _showsCashReceived
        ? _cashReceivedAmount
        : (_isCashPayment ? _invoiceTotal : 0.0);
    if (_showsCashReceived && cashReceivedAmount > _invoiceTotal) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('invalid_cash_received_amount'))));
      return;
    }
    final paidAmount = _derivedPaidAmount;
    final paymentStatus = _derivedPaymentStatus;
    late final Sale sale;
    try {
      sale = await widget.store.commerce.createSale(
          customerName: widget.store.commerce.resolveCustomerName(_selectedCustomerId),
          customerId: _selectedCustomerId,
          discount: _discount,
          originalDiscount:
              double.tryParse(_discountController.text.trim()) ?? 0,
          discountCurrency: _discountCurrency,
          discountExchangeRateAtEntry: exchangeRate(widget.store.runtime.profile.baseCurrency, _discountCurrency, widget.store.runtime.profile,
              effectiveAt: DateTime.now()),
          paymentMethod: _paymentMethod,
          paymentStatus: paymentStatus,
          invoiceCurrency: _invoiceCurrency,
          paymentCurrency: _paymentCurrency,
          exchangeRateAtPayment: _saleExchangeRate,
          paidAmount: paidAmount,
          cashReceivedAmount: cashReceivedAmount,
          paidAmountInPaymentCurrency: _isCreditPayment
              ? _cashReceivedInPaymentCurrency
              : _convertCurrencyAmount(
                  paidAmount, _invoiceCurrency, _paymentCurrency),
          cashReceivedAmountInPaymentCurrency: _isCashPayment
              ? _convertCurrencyAmount(
                  cashReceivedAmount, _invoiceCurrency, _paymentCurrency)
              : _cashReceivedInPaymentCurrency,
          warehouseId: _selectedWarehouseId,
          warehouseName: widget.store.inventory
              .resolveWarehouseForSale(warehouseId: _selectedWarehouseId)
              .name,
          items: _cart
              .map((item) => SaleItem(
                  productId: item.product.id,
                  productName: item.displayName,
                  unitPrice: item.unitPrice,
                  quantity: item.quantity,
                  unitName: item.unitName,
                  baseQuantity: item.baseQuantity,
                  conversionToBase: item.conversionToBase,
                  unitCost: 0))
              .toList());
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = _saleSaveFailureMessage(context, error);
      await _showTemporarySaleDebugDialog(
          context: context,
          error: error,
          stackTrace: stackTrace,
          userMessage: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    setState(() {
      _saleCart.clear();
      _selectedCartIndex = null;
      _pendingDeleteCartIndex = null;
      _discountController.clear();
      _paidAmountController.clear();
      _selectedCustomerId = CommerceDefaults.walkInCustomerId;
      _paymentMethod = 'Cash';
      _invoiceCurrency = widget.store.runtime.profile.defaultSaleInvoiceCurrency;
      _paymentCurrency = widget.store.runtime.profile.defaultSalePaymentCurrency;
      _discountCurrency = widget.store.runtime.profile.defaultSaleInvoiceCurrency;
      _selectedWarehouseId = widget.store.inventory
          .resolveWarehouseForSale(warehouseId: widget.store.inventory.saleWarehouseId)
          .id;
      _paymentExchangeRateController.text =
          widget.store.runtime.profile.usdToLbpRate.toStringAsFixed(0);
      _searchController.clear();
      _barcodeController.clear();
      _search = '';
    });
    _restoreScannerMode();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)
            .text('invoice_created_successfully'))));
    final printSettings = widget.store.runtime.profile.printSettings;
    final shouldPrint = printSettings.askBeforeSalesInvoicePrint
        ? await _confirmInvoicePrintAfterSave()
        : printSettings.printSalesInvoiceAfterSave;
    if (shouldPrint && mounted) {
      await _handleInvoiceAction(() => InvoicePdfService.printInvoice(
          context: context,
          sale: sale,
          profile: widget.store.runtime.profile,
          locale: AppLocalizations.of(context).locale));
    }
  }

  Future<void> _handleInvoiceAction(Future<void> Function() action,
      {String failureMessageKey = 'pdf_action_failed'}) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('Invoice action failed: $error\n$stackTrace');
      if (!mounted) return;
      final message = AppLocalizations.of(context).text(failureMessageKey);
      final errorText = error.toString();
      final visibleError = errorText.length > 320
          ? '${errorText.substring(0, 320)}…'
          : errorText;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 12),
          content: SelectableText('$message\n$visibleError')));
    }
  }
}
