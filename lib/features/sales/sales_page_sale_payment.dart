// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageSalePayment on _SalesPageState {
  String _saleSaveFailureMessage(BuildContext context, Object error) {
    final tr = AppLocalizations.of(context);
    if (error is StateError) {
      final raw = error.message.trim();
      if (raw.isNotEmpty) {
        return localizeRuntimeMessage(raw, tr);
      }
    }
    if (error is ArgumentError) {
      final raw = (error.message ?? '').toString().trim();
      if (raw.isNotEmpty &&
          (raw.contains('وردية') ||
              raw.contains('درج') ||
              raw.toLowerCase().contains('cash drawer') ||
              raw.toLowerCase().contains('device'))) {
        return localizeRuntimeMessage(raw, tr);
      }
      return tr.text('sale_validation_failed');
    }
    final raw = error.toString().trim();
    final normalized = raw
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Invalid argument\(s\):\s*'), '')
        .trim();
    if (normalized.isNotEmpty &&
        (normalized.contains('وردية') ||
            normalized.contains('درج') ||
            normalized.toLowerCase().contains('cash drawer') ||
            normalized.toLowerCase().contains('device'))) {
      return localizeRuntimeMessage(normalized, tr);
    }
    return tr.text('sale_validation_failed');
  }

  Future<void> _showTemporarySaleDebugDialog(
      {required BuildContext context,
      required Object error,
      required StackTrace stackTrace,
      required String userMessage}) async {
    final tr = AppLocalizations.of(context);
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer()
      ..writeln('VENTIO TEMP SALE DEBUG')
      ..writeln('time: $now')
      ..writeln('screen: sales_page')
      ..writeln('action: confirm_payment -> createSale')
      ..writeln('user_message: $userMessage')
      ..writeln('error_type: ${error.runtimeType}')
      ..writeln('error: $error')
      ..writeln('device_id: ${widget.store.deviceId}')
      ..writeln('payment_method: $_paymentMethod')
      ..writeln('payment_status: $_derivedPaymentStatus')
      ..writeln('invoice_currency: $_invoiceCurrency')
      ..writeln('payment_currency: $_paymentCurrency')
      ..writeln('subtotal: $_subtotal')
      ..writeln('discount: $_discount')
      ..writeln('raw_total: $_rawInvoiceTotal')
      ..writeln(
          'cash_rounding_difference: $_cashRoundingDifferenceInInvoiceCurrency')
      ..writeln('total: $_invoiceTotal')
      ..writeln(
          'cash_received: ${_showsCashReceived ? _cashReceivedAmount : (_isCashPayment ? _invoiceTotal : 0.0)}')
      ..writeln('paid_amount: $_derivedPaidAmount')
      ..writeln('selected_customer_id: $_selectedCustomerId')
      ..writeln('cart_items: ${_cart.length}');
    for (var i = 0; i < _cart.length; i += 1) {
      final item = _cart[i];
      buffer
        ..writeln('item[$i].product_id: ${item.product.id}')
        ..writeln('item[$i].name: ${item.product.name}')
        ..writeln('item[$i].code: ${item.product.code}')
        ..writeln('item[$i].quantity: ${item.quantity}')
        ..writeln('item[$i].unit_name: ${item.unitName}')
        ..writeln('item[$i].base_quantity: ${item.baseQuantity}')
        ..writeln('item[$i].conversion_to_base: ${item.conversionToBase}')
        ..writeln('item[$i].stock: ${item.product.stock}')
        ..writeln('item[$i].needs_auto_correction: ${item.needsAutoCorrection}')
        ..writeln('item[$i].unit_price: ${item.unitPrice}')
        ..writeln('item[$i].unit_cost: ${item.product.usdCost}');
    }
    buffer
      ..writeln('stack_trace:')
      ..writeln(stackTrace.toString());
    final debugText = buffer.toString();
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(tr.text('invoice_save_error_details')),
                content: SizedBox(
                    width: 680,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text(userMessage,
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .titleMedium),
                          const SizedBox(height: 12),
                          Text(tr.text('invoice_save_trace_explanation')),
                          const SizedBox(height: 12),
                          Container(
                              constraints: const BoxConstraints(maxHeight: 360),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12)),
                              child: SingleChildScrollView(
                                  child: SelectableText(debugText,
                                      textDirection: TextDirection.ltr,
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .bodySmall)))
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(tr.text('close'))),
                  FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: debugText));
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                                content:
                                    Text(tr.text('error_details_copied'))));
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(tr.text('copy')))
                ]));
  }

  Future<void> _createDeliveryNote(BuildContext context, Sale sale) async {
    if (!widget.store.canManageDeliveryNotes) return;
    final tr = AppLocalizations.of(context);
    try {
      await widget.store.createDeliveryNoteFromSale(sale.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('delivery_note_created'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  _BarcodeAddResult _addProduct(Product product,
      {ProductSaleUnit? saleUnit, bool showBarcodeFeedback = false}) {
    if (!widget.store.canSell) {
      if (showBarcodeFeedback) {
        _showBarcodeAddFeedback(_BarcodeAddResult.notAllowed);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)
                .text('role_not_allowed_to_sell'))));
      }
      _restoreScannerMode();
      return _BarcodeAddResult.notAllowed;
    }
    final rawSelectedUnit = saleUnit ?? product.effectiveSaleUnits.first;
    final selectedUnit = rawSelectedUnit.copyWith(
        price: _salePriceFor(product, rawSelectedUnit));
    final existingIndex = _cart.indexWhere((item) =>
        item.product.id == product.id &&
        item.unitName ==
            (selectedUnit.name.trim().isNotEmpty
                ? selectedUnit.name
                : product.unit));
    var result = _BarcodeAddResult.added;
    setState(() {
      if (existingIndex == -1) {
        _cart.insert(
            0,
            _DraftSaleItem(
                product: product, quantity: 1, saleUnit: selectedUnit));
      } else {
        _cart[existingIndex] = _cart[existingIndex]
            .copyWith(quantity: _cart[existingIndex].quantity + 1);
      }
      _selectedCartIndex = existingIndex == -1 ? 0 : existingIndex;
      _pendingDeleteCartIndex = null;
      final cartItem = _cart[_selectedCartIndex!];
      if (cartItem.needsAutoCorrection) {
        result = _BarcodeAddResult.autoCorrected;
      }
    });
    if (showBarcodeFeedback) {
      _showBarcodeAddFeedback(result);
    } else if (result == _BarcodeAddResult.autoCorrected) {
      unawaited(BarcodeFeedbackService.playError(force: true));
    }
    _restoreScannerMode();
    return result;
  }

  Future<_BarcodeProductMatch?> _barcodeMatchFromSqlite(String code) async {
    final row =
        await LocalDatabaseService.findSaleBarcodeProductFromSqlite(code);
    final productJson = row?['product'];
    if (productJson is! Map) return null;
    final product = Product.fromJson(Map<String, dynamic>.from(productJson));
    final unitId = row?['unitId']?.toString() ?? 'base';
    final unit = product.effectiveSaleUnits.firstWhere(
        (item) => item.id == unitId,
        orElse: () => product.effectiveSaleUnits.first);
    return _BarcodeProductMatch(product: product, unit: unit);
  }

  Future<_BarcodeAddResult> _addByCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      _restoreScannerMode();
      return _BarcodeAddResult.empty;
    }
    final match = await _barcodeMatchFromSqlite(cleanCode) ??
        _barcodeLookup()[cleanCode.toLowerCase()];
    if (match == null) {
      _barcodeController.clear();
      _showBarcodeAddFeedback(_BarcodeAddResult.notFound);
      _restoreScannerMode();
      return _BarcodeAddResult.notFound;
    }
    _barcodeController.clear();
    return _addProduct(match.product,
        saleUnit: match.unit, showBarcodeFeedback: true);
  }

  void _showBarcodeAddFeedback(_BarcodeAddResult result) {
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case _BarcodeAddResult.added:
        unawaited(BarcodeFeedbackService.play(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_product_added'))));
        return;
      case _BarcodeAddResult.autoCorrected:
        unawaited(BarcodeFeedbackService.playError(force: true));
        return;
      case _BarcodeAddResult.notFound:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_product_not_registered'))));
        return;
      case _BarcodeAddResult.outOfStock:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_out_of_stock'))));
        return;
      case _BarcodeAddResult.stockLimitReached:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_stock_limit_reached'))));
        return;
      case _BarcodeAddResult.notAllowed:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('role_not_allowed_to_sell'))));
        return;
      case _BarcodeAddResult.empty:
        return;
    }
  }

  Future<void> _openPaymentPage() async {
    if (!widget.store.canSell) return;
    if (_cart.isEmpty) return;
    await _refreshInvoiceBatchCostPreview();
    if (!mounted) return;
    _invoiceCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
    _discountCurrency = _invoiceCurrency;
    _syncDiscountPercentFromAmount();
    _paymentCurrency = widget.store.storeProfile.defaultSalePaymentCurrency;
    _paymentExchangeRateController.text =
        widget.store.storeProfile.usdToLbpRate.toStringAsFixed(0);
    if (_paymentMethod == 'Cash') {
      _paidAmountController.clear();
    } else if (_paidAmountController.text.trim().isEmpty) {
      _paidAmountController.text = '0';
    }
    final originalMethod = _paymentMethod;
    final originalPaymentCurrency = _paymentCurrency;
    final originalCash = _paidAmountController.text;
    final originalCustomerId = _selectedCustomerId;
    final originalDiscount = _discountController.text;
    final originalDiscountCurrency = _discountCurrency;
    final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (context, setDialogState) {
              final pageTr = AppLocalizations.of(context);
              final invoiceTotal = _invoiceTotal;
              final cashInInvoice = _cashReceivedAmount;
              final paidInInvoice = _derivedPaidAmount;
              final remaining = (invoiceTotal - paidInInvoice)
                  .clamp(0, double.infinity)
                  .toDouble();
              final nonCashOrCredit = (invoiceTotal - cashInInvoice)
                  .clamp(0, double.infinity)
                  .toDouble();
              return Focus(
                  focusNode: _paymentShortcutFocusNode,
                  autofocus: true,
                  onKeyEvent: (node, event) => _handlePaymentShortcutKey(
                          event, dialogContext, setDialogState)
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored,
                  child: AlertDialog(
                      title: Text(pageTr.text('payment_page')),
                      content: SizedBox(
                          width: 520,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                _buildPaymentShortcutGuide(context, pageTr),
                                const SizedBox(height: 8),
                                _buildCustomerSelector(context, pageTr,
                                    modalSetState: setDialogState),
                                const SizedBox(height: 16),
                                _buildPaymentMethodChips(pageTr,
                                    modalSetState: setDialogState),
                                const SizedBox(height: 16),
                                _buildPaymentCurrencySwitch(pageTr,
                                    modalSetState: setDialogState),
                                if (_showsCashReceived) ...[
                                  const SizedBox(height: 16),
                                  _buildCashReceivedField(pageTr,
                                      modalSetState: setDialogState)
                                ],
                                const SizedBox(height: 16),
                                Row(children: [
                                  Expanded(
                                      child: TextFormField(
                                          key: const ValueKey(
                                              'SalesPaymentDiscountField'),
                                          focusNode: _discountFocusNode,
                                          controller: _discountController,
                                          decoration: InputDecoration(
                                              labelText:
                                                  pageTr.text('discount'),
                                              suffixText: _discountCurrency),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}$'))
                                          ],
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          onChanged: (_) {
                                            _syncDiscountPercentFromAmount();
                                            setState(() => _discountCurrency =
                                                _invoiceCurrency);
                                            setDialogState(() {});
                                          })),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextFormField(
                                          key: const ValueKey(
                                              'SalesPaymentDiscountPercentField'),
                                          controller:
                                              _discountPercentController,
                                          decoration: InputDecoration(
                                              labelText: pageTr
                                                  .text('discount_percentage'),
                                              suffixText: '%'),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}$'))
                                          ],
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          onChanged: (_) {
                                            _syncDiscountAmountFromPercent();
                                            setState(() {});
                                            setDialogState(() {});
                                          }))
                                ]),
                                const SizedBox(height: 8),
                                Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                        onPressed: () => setDialogState(() {
                                              _showInvoiceProfit =
                                                  !_showInvoiceProfit;
                                            }),
                                        icon: Icon(_showInvoiceProfit
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                        label: Text(_showInvoiceProfit
                                            ? pageTr.text('hide_invoice_profit')
                                            : pageTr
                                                .text('show_invoice_profit')))),
                                if (_showInvoiceProfit)
                                  Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(
                                          '${pageTr.text('invoice_profit_amount')}: ${_formatSaleCurrency(_currencyFromBase(_invoiceProfitAmount, _invoiceCurrency), _invoiceCurrency)} • '
                                          '${pageTr.text('invoice_profit_percentage')}: ${_invoiceProfitPercent.toStringAsFixed(2)}%',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700))),
                                const Divider(height: 28),
                                _totalLine(
                                    pageTr.text('total'),
                                    _formatSaleCurrency(
                                        invoiceTotal, _invoiceCurrency),
                                    isBold: true),
                                if (_showsCashReceived)
                                  _totalLine(
                                      pageTr.text('cash_received_amount'),
                                      _formatSaleCurrency(
                                          cashInInvoice, _invoiceCurrency)),
                                if (_isCreditPayment)
                                  _totalLine(
                                      pageTr.text('remaining_debt'),
                                      _formatSaleCurrency(
                                          remaining, _invoiceCurrency),
                                      isBold: true)
                                else if (!_isCashPayment)
                                  _totalLine(
                                      pageTr.text('non_cash_amount'),
                                      _formatSaleCurrency(
                                          nonCashOrCredit, _invoiceCurrency),
                                      isBold: true)
                                else
                                  _totalLine(
                                      pageTr.text('paid_amount'),
                                      _formatSaleCurrency(
                                          invoiceTotal, _invoiceCurrency),
                                      isBold: true)
                              ]))),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(pageTr.text('cancel'))),
                        FilledButton.icon(
                            key: const ValueKey('SalesConfirmPaymentButton'),
                            onPressed: () => Navigator.pop(dialogContext, true),
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(pageTr.text('confirm_payment')))
                      ]));
            }));
    if (confirmed == true) {
      await _saveCurrentInvoice();
    } else if (mounted) {
      setState(() {
        _paymentMethod = originalMethod;
        _paymentCurrency = originalPaymentCurrency;
        _paidAmountController.text = originalCash;
        _selectedCustomerId = originalCustomerId;
        _discountController.text = originalDiscount;
        _discountCurrency = originalDiscountCurrency;
      });
    }
  }
}
