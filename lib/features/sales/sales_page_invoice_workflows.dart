// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageInvoiceWorkflows on _SalesPageState {
  Widget _totalLine(String title, String value, {bool isBold = false}) {
    final style = isBold
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(title), Text(value, style: style)]));
  }

  Future<void> _openSaleReturnDialog(BuildContext context) async {
    if (!widget.store.security.hasPermission(AppPermission.salesCancel)) return;
    final tr = AppLocalizations.of(context);
    await widget.store.commerce.ensureCreditNotesLoaded();
    if (!mounted || !context.mounted) return;
    const epsilon = 0.000001;
    Map<String, double> returnedFor(Sale sale) {
      final returned = <String, double>{};
      for (final note in widget.store.commerce.creditNotes) {
        if (note.originalSaleId != sale.id ||
            <String>{'cancelled', 'reversed', 'void'}
                .contains(note.status.trim().toLowerCase())) {
          continue;
        }
        for (final item in note.items) {
          returned.update(item.productId, (value) => value + item.quantity,
              ifAbsent: () => item.quantity);
        }
      }
      return returned;
    }

    final sources = widget.store.commerce.sales.where((sale) {
      if (sale.isDeleted || sale.isCancelled || sale.items.isEmpty) {
        return false;
      }
      final returned = returnedFor(sale);
      return sale.items.any(
          (item) => item.quantity - (returned[item.productId] ?? 0) > epsilon);
    }).toList(growable: false);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('no_sales_return_sources'))));
      return;
    }
    Sale? selected;
    final quantityControllers = <String, TextEditingController>{};
    String? dialogError;
    ({String sourceId, Map<String, double> quantities})? result;
    try {
      result = await showDialog<
              ({String sourceId, Map<String, double> quantities})>(
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (dialogContext, setDialogState) {
                final source = selected;
                final returned =
                    source == null ? <String, double>{} : returnedFor(source);
                final itemsByProduct = <String, SaleItem>{};
                final quantitiesByProduct = <String, double>{};
                if (source != null) {
                  for (final item in source.items) {
                    itemsByProduct.putIfAbsent(item.productId, () => item);
                    quantitiesByProduct.update(
                        item.productId, (value) => value + item.quantity,
                        ifAbsent: () => item.quantity);
                  }
                }
                final requestedByProduct = <String, double>{
                  for (final productId in quantitiesByProduct.keys)
                    productId: double.tryParse(
                            quantityControllers[productId]?.text.trim() ??
                                '') ??
                        0
                };
                var returnSubtotal = 0.0;
                if (source != null) {
                  final remainingByProduct = <String, double>{
                    for (final entry in requestedByProduct.entries)
                      entry.key: entry.value
                  };
                  for (final item in source.items) {
                    final requested = remainingByProduct[item.productId] ?? 0;
                    final quantity = math.min(item.quantity,
                        requested.clamp(0, double.infinity).toDouble());
                    if (quantity <= epsilon) continue;
                    returnSubtotal += quantity * item.unitPrice;
                    remainingByProduct[item.productId] = requested - quantity;
                  }
                }
                final returnAmount = source == null
                    ? 0.0
                    : normalizeAccountingAmount(
                        (returnSubtotal -
                                (source.subtotal <= 0
                                    ? 0
                                    : source.discount *
                                        (returnSubtotal / source.subtotal)))
                            .clamp(0, double.infinity)
                            .toDouble(),
                        source.invoiceCurrency,
                        widget.store.runtime.profile);
                final content = <Widget>[
                  DropdownButtonFormField<Sale>(
                      initialValue: selected,
                      decoration: InputDecoration(
                          labelText: tr.text('source_sale_invoice')),
                      isExpanded: true,
                      items: sources
                          .map((sale) => DropdownMenuItem<Sale>(
                              value: sale,
                              child: Text(
                                  '${sale.invoiceNo} — ${sale.customerName}')))
                          .toList(growable: false),
                      onChanged: (value) {
                        for (final controller in quantityControllers.values) {
                          controller.dispose();
                        }
                        quantityControllers.clear();
                        setDialogState(() {
                          selected = value;
                          dialogError = null;
                        });
                      }),
                  if (source != null) ...[
                    const SizedBox(height: 14),
                    Text(tr.text('select_return_items'),
                        style: Theme.of(dialogContext).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...itemsByProduct.entries.map((entry) {
                      final productId = entry.key;
                      final item = entry.value;
                      final available = (quantitiesByProduct[productId]! -
                              (returned[productId] ?? 0))
                          .clamp(0, double.infinity)
                          .toDouble();
                      final controller = quantityControllers.putIfAbsent(
                          productId, TextEditingController.new);
                      return Card(
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(item.productName),
                                      Text(
                                          '${tr.text('available_for_return')}: ${_formatQuantity(available)} ${item.unitName}',
                                          style: Theme.of(dialogContext)
                                              .textTheme
                                              .bodySmall)
                                    ])),
                                const SizedBox(width: 12),
                                SizedBox(
                                    width: 110,
                                    child: TextField(
                                        controller: controller,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                            labelText:
                                                tr.text('return_quantity')),
                                        onChanged: (_) => setDialogState(() {
                                              dialogError = null;
                                            })))
                              ])));
                    }),
                    const SizedBox(height: 8),
                    Card(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: .35),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(tr.text('final_total'),
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .titleMedium),
                                  Text(
                                      _formatSaleCurrency(
                                          returnAmount, source.invoiceCurrency),
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold))
                                ])))
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!,
                        style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error))
                  ]
                ];
                return AlertDialog(
                    title: Text(tr.text('new_sales_return')),
                    content: SizedBox(
                        width: 620,
                        child: SingleChildScrollView(
                            child: Column(children: content))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(tr.text('cancel'))),
                      FilledButton(
                          onPressed: source == null
                              ? null
                              : () {
                                  final quantities = <String, double>{};
                                  for (final entry
                                      in quantitiesByProduct.entries) {
                                    final quantity = double.tryParse(
                                            quantityControllers[entry.key]
                                                    ?.text
                                                    .trim() ??
                                                '') ??
                                        0;
                                    final available = (entry.value -
                                            (returned[entry.key] ?? 0))
                                        .clamp(0, double.infinity)
                                        .toDouble();
                                    if (!quantity.isFinite ||
                                        quantity < 0 ||
                                        quantity > available + epsilon) {
                                      setDialogState(() {
                                        dialogError =
                                            tr.text('select_return_items');
                                      });
                                      return;
                                    }
                                    if (quantity > epsilon) {
                                      quantities[entry.key] = quantity;
                                    }
                                  }
                                  if (quantities.isEmpty) {
                                    setDialogState(() {
                                      dialogError =
                                          tr.text('select_return_items');
                                    });
                                    return;
                                  }
                                  Navigator.pop(dialogContext, (
                                    sourceId: source.id,
                                    quantities: quantities
                                  ));
                                },
                          child: Text(tr.text('confirm')))
                    ]);
              }));
    } finally {
      for (final controller in quantityControllers.values) {
        controller.dispose();
      }
    }
    if (result == null || !context.mounted) return;
    if (!await requestSensitiveActionAuthorization(context, widget.store,
        action: SensitiveAction.saleReverse)) {
      return;
    }
    try {
      await widget.store.commerce.returnSale(result.sourceId,
          restoreStock: true, returnedQuantities: result.quantities);
      if (!mounted) return;
      setState(() {
        _salesQueryFuture = null;
        _salesQueryFutureKey = '';
        _invoiceDetailsFutureById.clear();
        _invoiceSearchIndexCache.invalidate();
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('invoice_return_created'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(localizedErrorText(tr, error))));
    }
  }

  Future<void> _showInvoicesSheet() async {
    final tr = AppLocalizations.of(context);
    await widget.store.commerce.ensureCreditNotesLoaded();
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) {
          return StatefulBuilder(builder: (context, setModalState) {
            void resetSearchState() {
              setModalState(() {
                _visibleInvoiceCount = 50;
                _salesQueryFuture = null;
                _invoiceDetailsFutureById.clear();
                _expandedInvoiceIds.clear();
              });
            }

            if (!LocalDatabaseService.canQueryBusinessSqlite) {
              return SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * 0.85,
                  child: _buildInvoicesPanelFromSales(
                      sheetContext, tr, widget.store.commerce.sales,
                      creditNotes: widget.store.commerce.creditNotes,
                      onSearchChanged: resetSearchState));
            }
            return FutureBuilder<_SalesQueryResult?>(
                future: _queryInvoicesFromSqlite(),
                builder: (context, snapshot) {
                  final result = snapshot.data;
                  if (result != null && !snapshot.hasError) {
                    return SizedBox(
                        height: MediaQuery.sizeOf(sheetContext).height * 0.85,
                        child: _buildInvoicesPanelFromSummaries(
                            sheetContext, tr, result.items,
                            creditNotes: widget.store.commerce.creditNotes,
                            setSheetState: setModalState,
                            totalCount: result.totalCount,
                            onSearchChanged: resetSearchState,
                            onLoadMore: result.hasMore
                                ? () {
                                    setModalState(() {
                                      _visibleInvoiceCount = math.min(
                                          result.totalCount,
                                          _visibleInvoiceCount + 50);
                                      _salesQueryFuture = null;
                                    });
                                  }
                                : null));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                        height: MediaQuery.sizeOf(sheetContext).height * 0.85,
                        child: const Center(
                            child: CircularProgressIndicator.adaptive()));
                  }
                  return SizedBox(
                      height: MediaQuery.sizeOf(sheetContext).height * 0.85,
                      child: _buildInvoicesPanelFromSales(
                          sheetContext, tr, widget.store.commerce.sales,
                          creditNotes: widget.store.commerce.creditNotes,
                          onSearchChanged: resetSearchState));
                });
          });
        });
  }

  Future<_SalesQueryResult?> _queryInvoicesFromSqlite() async {
    final query = _invoiceSearchController.text.trim().toLowerCase();
    final key = '${widget.store.commerce.salesRevision}|$_visibleInvoiceCount|$query';
    if (_salesQueryFuture == null || _salesQueryFutureKey != key) {
      _salesQueryFutureKey = key;
      _salesQueryFuture = () async {
        final page = await LocalDatabaseService.querySaleSummariesFromSqlite(
            query: query, limit: _visibleInvoiceCount);
        if (page == null) return null;
        return _SalesQueryResult(
            items: page.items, totalCount: page.totalCount);
      }();
    }
    return _salesQueryFuture!;
  }

  Widget _buildInvoicesPanelFromSales(
      BuildContext context, AppLocalizations tr, List<Sale> sales,
      {List<CreditNote> creditNotes = const [],
      int totalCount = 0,
      VoidCallback? onLoadMore,
      VoidCallback? onSearchChanged}) {
    final query = _invoiceSearchController.text.trim().toLowerCase();
    final searchIndex = _invoiceSearchIndex(sales);
    final filteredSales = query.isEmpty
        ? sales
        : sales
            .where((sale) => searchIndex[sale.id]?.contains(query) ?? false)
            .toList(growable: false);
    final displaySales = onLoadMore == null && filteredSales.length > 50
        ? filteredSales.take(50).toList()
        : filteredSales;
    final displayCreditNotes = creditNotes
        .where((note) => _creditNoteMatches(note, query))
        .toList(growable: false);
    final entries = <Object>[...displaySales, ...displayCreditNotes]
      ..sort((a, b) => _invoiceEntryDate(b).compareTo(_invoiceEntryDate(a)));
    return Card(
        child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.text('recent_invoices'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _invoiceSearchController,
                  onChanged: (_) => onSearchChanged?.call(),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr.text('search'),
                      border: const OutlineInputBorder(),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr.text('clear_search'),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _invoiceSearchController.clear();
                                onSearchChanged?.call();
                              }))),
              const SizedBox(height: 12),
              Expanded(
                  child: entries.isEmpty
                      ? EmptyStateCard(
                          icon: Icons.receipt_long_outlined,
                          title: tr.text('no_sales'),
                          subtitle: tr.text('no_sales_desc'))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry is CreditNote) {
                              return _buildCreditNoteTile(context, tr, entry);
                            }
                            final sale = entry as Sale;
                            return ExpansionTile(
                                leading: Icon(sale.isCancelled
                                    ? Icons.cancel_outlined
                                    : Icons.check_circle),
                                title: Text(sale.invoiceNo),
                                subtitle: Text(
                                    '${sale.customerName} • ${sale.date.toLocal()}'
                                        .split('.')
                                        .first),
                                trailing: Text(sale.isCancelled
                                    ? sale.status
                                    : formatUsdReferenceAmount(
                                        sale.total, widget.store.runtime.profile)),
                                children: [
                                  ...sale.items.map((item) => ListTile(
                                      dense: true,
                                      title: Text(item.productName),
                                      subtitle: Text(
                                          '${tr.text('quantity')}: ${_formatQuantity(item.quantity)} ${item.unitName} × ${formatUsdReferenceAmount(item.unitPrice, widget.store.runtime.profile)}'),
                                      trailing: Text(formatUsdReferenceAmount(
                                          item.lineTotal,
                                          widget.store.runtime.profile)))),
                                  const Divider(height: 1),
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 12),
                                      child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                                onPressed: widget.store
                                                        .security.hasPermission(
                                                            AppPermission
                                                                .salesPrint)
                                                    ? () => _handleInvoiceAction(() =>
                                                        InvoicePdfService.printInvoice(
                                                            context: context,
                                                            sale: sale,
                                                            profile: widget
                                                                .store
                                                                .runtime.profile,
                                                            locale:
                                                                AppLocalizations.of(
                                                                        context)
                                                                    .locale))
                                                    : null,
                                                icon:
                                                    const Icon(Icons.print_outlined),
                                                label: Text(tr.text('print_invoice'))),
                                            OutlinedButton.icon(
                                                onPressed: widget.store
                                                        .security.hasPermission(
                                                            AppPermission
                                                                .salesExport)
                                                    ? () => _handleInvoiceAction(() =>
                                                        InvoicePdfService.shareInvoice(
                                                            sale: sale,
                                                            profile: widget
                                                                .store
                                                                .runtime.profile,
                                                            locale:
                                                                AppLocalizations.of(
                                                                        context)
                                                                    .locale))
                                                    : null,
                                                icon: const Icon(Icons.share_outlined),
                                                label: Text(tr.text('share_pdf'))),
                                            OutlinedButton.icon(
                                                onPressed: (!sale.isCancelled &&
                                                        widget.store
                                                            .security.hasPermission(
                                                                AppPermission
                                                                    .salesEdit))
                                                    ? () => _editPostedSale(
                                                        context, sale)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                                label:
                                                    Text(tr.text('edit_sale'))),
                                            OutlinedButton.icon(
                                                onPressed: (!sale.isCancelled &&
                                                        widget.store
                                                            .security.hasPermission(
                                                                AppPermission
                                                                    .salesCancel))
                                                    ? () => _returnSale(
                                                        context, sale)
                                                    : null,
                                                icon: const Icon(Icons
                                                    .assignment_return_outlined),
                                                label:
                                                    Text(_saleReturnLabel(tr))),
                                            OutlinedButton.icon(
                                                onPressed: (widget.store
                                                            .security.hasPermission(
                                                                AppPermission
                                                                    .salesEdit) &&
                                                        widget.store.security.hasPermission(
                                                            AppPermission
                                                                .salesCancel) &&
                                                        _latestActiveCreditNoteForSale(
                                                                sale.id) !=
                                                            null)
                                                    ? () => _editLatestSaleReturn(
                                                        context, sale)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.edit_note_outlined),
                                                label: Text(
                                                    '${tr.text('edit')} ${_saleReturnLabel(tr)}')),
                                            OutlinedButton.icon(
                                                onPressed: (!sale.isCancelled &&
                                                        widget.store
                                                                .commerce.deliveryNoteForSale(
                                                                    sale.id) ==
                                                            null &&
                                                        widget.store
                                                            .security.canManageDeliveryNotes)
                                                    ? () => _createDeliveryNote(
                                                        context, sale)
                                                    : null,
                                                icon: const Icon(Icons
                                                    .local_shipping_outlined),
                                                label: Text(
                                                    tr.text('delivery_note')))
                                          ]))
                                ]);
                          })),
              if (onLoadMore != null && displaySales.length < totalCount) ...[
                const SizedBox(height: 12),
                Align(
                    alignment: Alignment.center,
                    child: OutlinedButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: Text(tr.text('load_more'))))
              ]
            ])));
  }

  Widget _buildInvoicesPanelFromSummaries(
      BuildContext context, AppLocalizations tr, List<SaleSummary> sales,
      {List<CreditNote> creditNotes = const [],
      required void Function(VoidCallback fn) setSheetState,
      int totalCount = 0,
      VoidCallback? onLoadMore,
      VoidCallback? onSearchChanged}) {
    final query = _invoiceSearchController.text.trim().toLowerCase();
    final displaySales = sales;
    final displayCreditNotes = creditNotes
        .where((note) => _creditNoteMatches(note, query))
        .toList(growable: false);
    final entries = <Object>[...displaySales, ...displayCreditNotes]
      ..sort((a, b) => _invoiceEntryDate(b).compareTo(_invoiceEntryDate(a)));
    return Card(
        child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.text('recent_invoices'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _invoiceSearchController,
                  onChanged: (_) => onSearchChanged?.call(),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr.text('search'),
                      border: const OutlineInputBorder(),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr.text('clear_search'),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _invoiceSearchController.clear();
                                onSearchChanged?.call();
                              }))),
              const SizedBox(height: 12),
              Expanded(
                  child: entries.isEmpty
                      ? EmptyStateCard(
                          icon: Icons.receipt_long_outlined,
                          title: tr.text('no_sales'),
                          subtitle: tr.text('no_sales_desc'))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry is CreditNote) {
                              return _buildCreditNoteTile(context, tr, entry);
                            }
                            final summary = entry as SaleSummary;
                            final expanded =
                                _expandedInvoiceIds.contains(summary.id);
                            return ExpansionTile(
                                key: PageStorageKey<String>(
                                    'invoice_summary_${summary.id}'),
                                initiallyExpanded: expanded,
                                onExpansionChanged: (isExpanded) {
                                  setSheetState(() {
                                    if (isExpanded) {
                                      _expandedInvoiceIds.add(summary.id);
                                      _invoiceDetailsFutureById.putIfAbsent(
                                          summary.id,
                                          () => LocalDatabaseService
                                              .getSaleFromSqliteById(
                                                  summary.id));
                                    } else {
                                      _expandedInvoiceIds.remove(summary.id);
                                    }
                                  });
                                },
                                leading: Icon(summary.isCancelled
                                    ? Icons.cancel_outlined
                                    : Icons.check_circle),
                                title: Text(summary.invoiceNo),
                                subtitle: Text(
                                    '${summary.customerName} • ${summary.date.toLocal().toString().split('.').first} • ${summary.productCount} items'),
                                trailing: Text(summary.isCancelled
                                    ? summary.status
                                    : formatUsdReferenceAmount(summary.total,
                                        widget.store.runtime.profile)),
                                children: [
                                  if (!expanded)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 12),
                                        child: Text(
                                            tr.text('tap_to_load_details')))
                                  else
                                    FutureBuilder<Sale?>(
                                        future: _invoiceDetailsFutureById[
                                                summary.id] ??
                                            LocalDatabaseService
                                                .getSaleFromSqliteById(
                                                    summary.id),
                                        builder: (context, snapshot) {
                                          final sale = snapshot.data;
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                    16, 0, 16, 12),
                                                child: Center(
                                                    child: Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                vertical: 16),
                                                        child:
                                                            CircularProgressIndicator
                                                                .adaptive())));
                                          }
                                          if (sale == null) {
                                            return Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                    16, 0, 16, 12),
                                                child: Text(tr.text(
                                                    'no_sale_details_found')));
                                          }
                                          return _buildInvoiceDetailsContent(
                                              context, tr, sale);
                                        })
                                ]);
                          })),
              if (onLoadMore != null && displaySales.length < totalCount) ...[
                const SizedBox(height: 12),
                Align(
                    alignment: Alignment.center,
                    child: OutlinedButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: Text(tr.text('load_more'))))
              ]
            ])));
  }

  Widget _buildInvoiceDetailsContent(
      BuildContext context, AppLocalizations tr, Sale sale) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...sale.items.map((item) => ListTile(
          dense: true,
          title: Text(item.productName),
          subtitle: Text(
              '${tr.text('quantity')}: ${_formatQuantity(item.quantity)} ${item.unitName} × ${formatUsdReferenceAmount(item.unitPrice, widget.store.runtime.profile)}'),
          trailing: Text(formatUsdReferenceAmount(
              item.lineTotal, widget.store.runtime.profile)))),
      const Divider(height: 1),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: widget.store.security.hasPermission(AppPermission.salesPrint)
                    ? () => _handleInvoiceAction(() =>
                        InvoicePdfService.printInvoice(
                            context: context,
                            sale: sale,
                            profile: widget.store.runtime.profile,
                            locale: AppLocalizations.of(context).locale))
                    : null,
                icon: const Icon(Icons.print_outlined),
                label: Text(tr.text('print_invoice'))),
            OutlinedButton.icon(
                onPressed: widget.store.security.hasPermission(AppPermission.salesExport)
                    ? () => _handleInvoiceAction(() =>
                        InvoicePdfService.shareInvoice(
                            sale: sale,
                            profile: widget.store.runtime.profile,
                            locale: AppLocalizations.of(context).locale))
                    : null,
                icon: const Icon(Icons.share_outlined),
                label: Text(tr.text('share_pdf'))),
            OutlinedButton.icon(
                onPressed: (!sale.isCancelled &&
                        widget.store.security.hasPermission(AppPermission.salesEdit))
                    ? () => _editPostedSale(context, sale)
                    : null,
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr.text('edit_sale'))),
            OutlinedButton.icon(
                onPressed: (!sale.isCancelled &&
                        widget.store.security.hasPermission(AppPermission.salesCancel))
                    ? () => _returnSale(context, sale)
                    : null,
                icon: const Icon(Icons.assignment_return_outlined),
                label: Text(_saleReturnLabel(tr))),
            OutlinedButton.icon(
                onPressed: (widget.store
                            .security.hasPermission(AppPermission.salesEdit) &&
                        widget.store.security.hasPermission(AppPermission.salesCancel) &&
                        _latestActiveCreditNoteForSale(sale.id) != null)
                    ? () => _editLatestSaleReturn(context, sale)
                    : null,
                icon: const Icon(Icons.edit_note_outlined),
                label: Text('${tr.text('edit')} ${_saleReturnLabel(tr)}')),
            OutlinedButton.icon(
                onPressed: (!sale.isCancelled &&
                        widget.store.commerce.deliveryNoteForSale(sale.id) == null &&
                        widget.store.security.canManageDeliveryNotes)
                    ? () => _createDeliveryNote(context, sale)
                    : null,
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(tr.text('delivery_note')))
          ]))
    ]);
  }
}
