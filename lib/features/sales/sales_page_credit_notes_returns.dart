// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageCreditNotesReturns on _SalesPageState {
  bool _creditNoteMatches(CreditNote note, String query) {
    if (query.isEmpty) return true;
    final haystack = <String>[
      note.creditNoteNo,
      note.originalInvoiceNo,
      note.customerName,
      note.customerId,
      note.note,
      note.status,
      ...note.items.map((item) => item.productName)
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  DateTime _invoiceEntryDate(Object entry) {
    if (entry is CreditNote) return entry.date;
    if (entry is Sale) return entry.date;
    return (entry as SaleSummary).date;
  }

  Widget _buildCreditNoteTile(
      BuildContext context, AppLocalizations tr, CreditNote note) {
    final status = note.status.trim().toLowerCase();
    final isInactive =
        status == 'cancelled' || status == 'reversed' || status == 'void';
    final isLatestActive = !isInactive &&
        _latestActiveCreditNoteForSale(note.originalSaleId)?.id == note.id;
    final amount = formatCurrency(note.amount,
        currency: note.currency, profile: widget.store.runtime.profile);
    return ExpansionTile(
        key: PageStorageKey<String>('credit_note_${note.id}'),
        leading: Icon(isInactive
            ? Icons.cancel_outlined
            : Icons.assignment_return_outlined),
        title: Text(note.creditNoteNo),
        subtitle: Text('${tr.text('sale_return')} • ${note.customerName} • '
            '${note.date.toLocal().toString().split('.').first}'),
        trailing: Text('−$amount',
            style: TextStyle(
                color:
                    isInactive ? null : Theme.of(context).colorScheme.error)),
        children: [
          ListTile(
              dense: true,
              title:
                  Text('${tr.text('sale_invoice')}: ${note.originalInvoiceNo}'),
              subtitle: Text(note.status.trim().isEmpty
                  ? tr.text('sale_return')
                  : note.status)),
          ...note.items.map((item) => ListTile(
              dense: true,
              title: Text(item.productName),
              subtitle: Text(
                  '${tr.text('quantity')}: ${_formatQuantity(item.quantity)} ${item.unitName} × '
                  '${formatCurrency(item.unitPrice, currency: note.currency, profile: widget.store.runtime.profile)}'),
              trailing: Text(formatCurrency(item.lineTotal,
                  currency: note.currency,
                  profile: widget.store.runtime.profile)))),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('${tr.text('total')}: $amount',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (widget.store.security
                          .hasPermission(AppPermission.salesPrint))
                        OutlinedButton.icon(
                            onPressed: () => _handleInvoiceAction(() =>
                                InvoicePdfService.printSaleReturn(
                                    context: context,
                                    creditNote: note,
                                    profile: widget.store.runtime.profile,
                                    locale:
                                        AppLocalizations.of(context).locale)),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(tr.text('print_invoice'))),
                      if (isLatestActive &&
                          widget.store.security
                              .hasPermission(AppPermission.salesEdit) &&
                          widget.store.security
                              .hasPermission(AppPermission.salesCancel))
                        FilledButton.icon(
                            onPressed: () => _editCreditNote(context, note),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                                '${tr.text('edit')} ${_saleReturnLabel(tr)}')),
                      if (isLatestActive &&
                          widget.store.security
                              .hasPermission(AppPermission.salesCancel))
                        OutlinedButton.icon(
                            onPressed: () => _cancelSaleReturn(context, note),
                            icon: const Icon(Icons.cancel_outlined),
                            label: Text(tr.text('cancel_sales_return')))
                    ])
                  ]))
        ]);
  }

  Future<void> _editCreditNote(BuildContext context, CreditNote note) async {
    Sale? sale;
    for (final candidate in widget.store.commerce.sales) {
      if (candidate.id == note.originalSaleId) {
        sale = candidate;
        break;
      }
    }
    sale ??=
        await LocalDatabaseService.getSaleFromSqliteById(note.originalSaleId);
    if (!context.mounted) return;
    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('no_sale_details_found'))));
      return;
    }
    await _editLatestSaleReturn(context, sale);
  }

  Future<void> _cancelSaleReturn(BuildContext context, CreditNote note) async {
    if (!widget.store.security.hasPermission(AppPermission.salesCancel)) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(tr.text('cancel_sales_return')),
                content: Text(tr.format('cancel_sales_return_confirm',
                    {'invoice': note.creditNoteNo})),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(tr.text('cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(tr.text('confirm')))
                ]));
    if (confirmed != true || !context.mounted) return;
    if (!await requestSensitiveActionAuthorization(context, widget.store,
        action: SensitiveAction.saleReverse)) {
      return;
    }
    try {
      await widget.store.commerce.cancelSaleReturn(
          creditNoteId: note.id, expectedVersion: note.version);
      if (!mounted) return;
      setState(() {
        _salesQueryFuture = null;
        _salesQueryFutureKey = '';
        _invoiceDetailsFutureById.clear();
        _invoiceSearchIndexCache.invalidate();
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('sales_return_cancelled'))));
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(localizedErrorText(tr, error))));
    }
  }

  Map<String, String> _invoiceSearchIndex(List<Sale> sales) {
    return _invoiceSearchIndexCache.getOrCompute(
        widget.store.commerce.salesRevision, 'recent_invoices_search_index',
        () {
      final index = <String, String>{};
      for (final sale in sales) {
        final buffer = StringBuffer()
          ..write(sale.invoiceNo)
          ..write(' ')
          ..write(sale.customerName)
          ..write(' ')
          ..write(sale.note)
          ..write(' ')
          ..write(sale.status)
          ..write(' ')
          ..write(sale.id);
        for (final item in sale.items) {
          buffer
            ..write(' ')
            ..write(item.productName)
            ..write(' ')
            ..write(item.unitName);
        }
        index[sale.id] = buffer.toString().toLowerCase();
      }
      return index;
    });
  }

  void _changeCartQuantity(int index, double quantity) {
    if (index < 0 || index >= _cart.length) return;
    var willNeedCorrection = false;
    setState(() {
      willNeedCorrection = _saleCart.changeQuantity(index, quantity);
      _selectedCartIndex = index;
      _pendingDeleteCartIndex = null;
    });
    if (willNeedCorrection) {
      unawaited(BarcodeFeedbackService.playError(force: true));
    }
  }

  void _commitCartQuantityText(int index, String value) {
    final quantity = double.tryParse(value.trim());
    if (quantity == null || !quantity.isFinite) return;
    _changeCartQuantity(index, quantity);
  }
}
