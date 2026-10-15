// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_page.dart';

extension _PurchasesPageStateMethods2 on _PurchasesPageState {
  Future<void> _deleteDraftPurchase(BuildContext context, String id) async {
    if (!widget.store.security.canManagePurchases) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('delete_draft_purchase')),
        content: Text(
            AppLocalizations.of(context).text('delete_draft_purchase_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              key: const ValueKey('PurchaseDeleteDraftConfirmButton'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).text('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.commerce.deleteDraftPurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('purchase_deleted'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<void> _returnPurchase(BuildContext context, String id) async {
    // Purchase managers should always use the independent partial-return
    // document. Keep the legacy full-reversal flow only for cancellation-only
    // roles that do not have permission to create purchase documents.
    if (widget.store.security.canManagePurchases) {
      await _openPurchaseReturnDialog(
        context,
        sourcePurchaseId: id,
      );
      return;
    }
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.purchasesCancel,
      AppPermission.purchasesManage,
    })) {
      return;
    }
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('return_purchase')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppLocalizations.of(context).text('return_purchase_desc')),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('PurchaseReturnReasonField'),
              controller: reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)
                      .text('return_reason_optional')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              key: const ValueKey('PurchaseReturnConfirmButton'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).text('confirm'))),
        ],
      ),
    );
    if (ok != true) {
      reasonController.dispose();
      return;
    }
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (!context.mounted) return;
    if (!await requestSensitiveActionAuthorization(
      context,
      widget.store,
      action: SensitiveAction.purchaseReverse,
    )) {
      return;
    }
    try {
      await widget.store.commerce.returnPurchase(id, reason: reason);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('purchase_returned_stock_reversed'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<void> _openPurchaseReturnDialog(
    BuildContext context, {
    String? sourcePurchaseId,
  }) async {
    final tr = AppLocalizations.of(context);
    final sources = widget.store.commerce.purchases
        .where((purchase) =>
            purchase.isReceived &&
            !purchase.isCancelled &&
            !purchase.isPurchaseReturn)
        .toList(growable: false);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('no_purchase_return_sources'))),
      );
      return;
    }
    Purchase? selected;
    if (sourcePurchaseId != null) {
      for (final purchase in sources) {
        if (purchase.id == sourcePurchaseId) {
          selected = purchase;
          break;
        }
      }
    }
    final reasonController = TextEditingController();
    final quantityControllers = <String, TextEditingController>{};
    String? dialogError;
    ({String sourceId, List<PurchaseItem> items, String reason})? result;
    result = await showDialog<
        ({String sourceId, List<PurchaseItem> items, String reason})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final source = selected;
          final sourceItems = source?.items ?? const <PurchaseItem>[];
          final content = <Widget>[
            DropdownButtonFormField<Purchase>(
              initialValue: selected,
              decoration: InputDecoration(
                  labelText: tr.text('source_purchase_invoice')),
              isExpanded: true,
              items: sources
                  .map((purchase) => DropdownMenuItem<Purchase>(
                        value: purchase,
                        child: Text(
                            '${purchase.purchaseNo} — ${purchase.supplierName}'),
                      ))
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
              },
            ),
            if (source != null) ...[
              const SizedBox(height: 14),
              Text(tr.text('select_return_items'),
                  style: Theme.of(dialogContext).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...sourceItems.indexed.map((entry) {
                final index = entry.$1;
                final item = entry.$2;
                final lineId = item.lineId.trim().isEmpty
                    ? '${source.id}:line:$index'
                    : item.lineId;
                final controller = quantityControllers.putIfAbsent(
                    lineId, TextEditingController.new);
                final alreadyReturned = widget.store.commerce.purchases
                    .where((purchase) =>
                        purchase.isPurchaseReturn &&
                        purchase.sourcePurchaseId == source.id)
                    .expand((purchase) => purchase.items)
                    .where((returnItem) => returnItem.sourceLineId == lineId)
                    .fold<double>(0, (sum, item) => sum + item.baseQuantity);
                final available = ((item.baseQuantity - alreadyReturned) /
                        (item.conversionToBase <= 0
                            ? 1
                            : item.conversionToBase))
                    .clamp(0, double.infinity)
                    .toDouble();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName),
                              Text(
                                '${tr.text('available_for_return')}: ${_formatQuantity(available)} ${item.purchaseUnitName}',
                                style:
                                    Theme.of(dialogContext).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: tr.text('return_quantity')),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: tr.text('return_reason_optional')),
              ),
            ],
            if (dialogError != null) ...[
              const SizedBox(height: 8),
              Text(dialogError!,
                  style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error)),
            ],
          ];
          return AlertDialog(
            title: Text(tr.text('new_purchase_return')),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(child: Column(children: content)),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: source == null
                    ? null
                    : () {
                        final selectedItems = <PurchaseItem>[];
                        for (final entry in source.items.indexed) {
                          final item = entry.$2;
                          final lineId = item.lineId.trim().isEmpty
                              ? '${source.id}:line:${entry.$1}'
                              : item.lineId;
                          final quantity = double.tryParse(
                                  quantityControllers[lineId]?.text.trim() ??
                                      '') ??
                              0;
                          if (quantity <= 0) continue;
                          selectedItems.add(PurchaseItem(
                            sourceLineId: lineId,
                            productId: item.productId,
                            productName: item.productName,
                            quantity: quantity,
                            unitCost: item.unitCost,
                            purchaseUnitId: item.purchaseUnitId,
                            purchaseUnitName: item.purchaseUnitName,
                            conversionToBase: item.conversionToBase,
                            originalUnitCost: item.originalUnitCost,
                            unitCostCurrency: item.unitCostCurrency,
                            exchangeRateAtEntry: item.exchangeRateAtEntry,
                            batchAllocations: item.batchAllocations,
                          ));
                        }
                        if (selectedItems.isEmpty) {
                          setDialogState(() =>
                              dialogError = tr.text('select_return_items'));
                          return;
                        }
                        Navigator.pop(dialogContext, (
                          sourceId: source.id,
                          items: selectedItems,
                          reason: reasonController.text.trim(),
                        ));
                      },
                child: Text(tr.text('confirm')),
              ),
            ],
          );
        },
      ),
    );
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    reasonController.dispose();
    if (result == null || !context.mounted) return;
    final selection = result;
    if (!await requestSensitiveActionAuthorization(
      context,
      widget.store,
      action: SensitiveAction.purchaseReverse,
    )) {
      return;
    }
    try {
      await widget.store.commerce.createPurchaseReturn(
        sourcePurchaseId: selection.sourceId,
        items: selection.items,
        reason: selection.reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('purchase_return_created'))),
      );
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedErrorText(tr, error))),
      );
    }
  }

  Future<void> _showPurchaseDetails(
      BuildContext context, Purchase purchase) async {
    final parentContext = context;
    final tr = AppLocalizations.of(parentContext);
    final statusText = purchase.isPurchaseReturn
        ? tr.text('purchase_return')
        : purchase.isReturned
            ? tr.text('returned')
            : purchase.status.toLowerCase() == 'cancelled'
                ? tr.text('cancelled')
                : purchase.isReceived
                    ? tr.text('received')
                    : tr.text('draft');
    final statusColor = purchase.isPurchaseReturn
        ? Colors.blueGrey
        : purchase.isReturned
            ? Colors.blueGrey
            : purchase.status.toLowerCase() == 'cancelled'
                ? Colors.red
                : purchase.isReceived
                    ? Colors.green
                    : Colors.orange;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) => Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(purchase.purchaseNo,
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                        label: Text(purchase.supplierName.isEmpty
                            ? '-'
                            : purchase.supplierName),
                        avatar: const Icon(Icons.local_shipping_outlined,
                            size: 18)),
                    Chip(
                        label: Text(statusText),
                        avatar:
                            Icon(Icons.circle, size: 14, color: statusColor)),
                    Chip(
                        label: Text(
                            '${purchase.items.length} ${tr.text('items')}')),
                    Chip(
                        label: Text(
                            '${_formatQuantity(purchase.totalUnits)} ${tr.text('units')}')),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: VentioResponsive.cardInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                            label: tr.text('date'),
                            value: _formatShortDate(purchase.date)),
                        if (purchase.isPurchaseReturn &&
                            purchase.sourcePurchaseNo.trim().isNotEmpty)
                          _DetailRow(
                              label: tr.text('source_purchase_invoice'),
                              value: purchase.sourcePurchaseNo),
                        if (purchase.cancelledAt != null)
                          _DetailRow(
                              label: tr.text('cancelled_at'),
                              value: _formatShortDate(purchase.cancelledAt!)),
                        if (purchase.cancelReason.trim().isNotEmpty)
                          _DetailRow(
                              label: tr.text('cancel_reason'),
                              value: purchase.cancelReason.trim()),
                        if (purchase.isCancelled)
                          _DetailRow(
                              label: tr.text('reversal_status'),
                              value: purchase.reversalApplied
                                  ? tr.text('reversal_applied')
                                  : tr.text('reversal_not_applied')),
                        _DetailRow(
                            label: tr.text('final_total'),
                            value: formatUsdReferenceAmount(
                                purchase.subtotal, widget.store.runtime.profile)),
                        if (purchase.note.trim().isNotEmpty)
                          _DetailRow(
                              label: tr.text('notes'),
                              value: purchase.note.trim()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr.text('items'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...purchase.items.map((item) => Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                            '${_formatQuantity(item.quantity)} ${item.purchaseUnitName.isEmpty ? tr.text('unit') : item.purchaseUnitName} • ${formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency)}'),
                        trailing: Text(formatUsdReferenceAmount(
                            item.lineTotal, widget.store.runtime.profile)),
                      ),
                    )),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (widget.store
                        .security.hasPermission(AppPermission.purchasesPrint))
                      OutlinedButton.icon(
                        onPressed: () => _printPurchase(context, purchase),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(tr.text('print_invoice')),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        if (!parentContext.mounted) return;
                        _openPurchaseDialog(parentContext, template: purchase);
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(tr.text('duplicate_purchase')),
                    ),
                    if (((purchase.isDraft || purchase.isReceived) &&
                            !purchase.isCancelled &&
                            !purchase.isReturned &&
                            !purchase.isPurchaseReturn &&
                            widget.store.security.canManagePurchases) ||
                        (purchase.isReturned &&
                            widget.store.security.canManagePurchases &&
                            widget.store
                                .security.hasPermission(AppPermission.purchasesCancel)))
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!parentContext.mounted) return;
                          _openPurchaseDialog(parentContext,
                              editPurchase: purchase);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(tr.text('edit_purchase')),
                      ),
                    if (!purchase.isReceived && !purchase.isCancelled)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!parentContext.mounted) return;
                          _receivePurchase(parentContext, purchase.id);
                        },
                        icon: const Icon(Icons.download_done),
                        label: Text(tr.text('receive')),
                      ),
                    if (purchase.isReceived &&
                        !purchase.isReturned &&
                        !purchase.isPurchaseReturn)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!parentContext.mounted) return;
                          _returnPurchase(parentContext, purchase.id);
                        },
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: Text(tr.text('return_purchase')),
                      ),
                    if (!purchase.isReceived && !purchase.isCancelled)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!parentContext.mounted) return;
                          _deleteDraftPurchase(parentContext, purchase.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(tr.text('delete_draft_purchase')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _printPurchase(BuildContext context, Purchase purchase) async {
    final tr = AppLocalizations.of(context);
    try {
      await PurchasePdfService.printPurchase(
        context: context,
        purchase: purchase,
        profile: widget.store.runtime.profile,
        locale: tr.locale,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('pdf_action_failed'))),
      );
    }
  }

  Future<void> _openPurchaseDialog(BuildContext context,
      {Purchase? template, Purchase? editPurchase}) async {
    if (!widget.store.security.canManagePurchases) return;
    final tr = AppLocalizations.of(context);
    // The list/details view may hold an older version after another user or
    // device updated the invoice. Always build the edit form from SQLite's
    // latest snapshot; the save path still performs the final version check.
    if (editPurchase != null) {
      final latest =
          await widget.store.commerce.reloadPurchaseFromSqlite(editPurchase.id);
      if (latest == null) return;
      editPurchase = latest;
    }
    final formKey = GlobalKey<FormState>();
    final source = editPurchase ?? template;
    final items =
        source == null ? <PurchaseItem>[] : List<PurchaseItem>.of(source.items);
    final sqliteProducts = await LocalDatabaseService.queryProductsFromSqlite(
      limit: 250,
      activeOnly: true,
      stockTrackedOnly: true,
    );
    final sqliteSuppliers = await LocalDatabaseService.querySuppliersFromSqlite(
      limit: 250,
    );
    if (!mounted || !context.mounted) return;
    var purchaseProducts = sqliteProducts?.items ??
        widget.store.catalog.products
            .where((product) => product.trackStock && product.isActive)
            .toList();
    var purchaseSuppliers = sqliteSuppliers?.items ??
        widget.store.commerce.suppliers.toList(growable: false);
    String supplierId = source?.supplierId ??
        (purchaseSuppliers.isNotEmpty ? purchaseSuppliers.first.id : '');
    String supplierName = source?.supplierName ??
        (purchaseSuppliers.isNotEmpty ? purchaseSuppliers.first.name : '');
    final initialWarehouse = widget.store.inventory.resolveWarehouseForPurchase(
      warehouseId: source?.warehouseId ?? '',
    );
    String selectedWarehouseId = initialWarehouse.id;
    String selectedWarehouseName = source?.warehouseName.isNotEmpty == true
        ? source!.warehouseName
        : initialWarehouse.name;
    if (supplierId.isNotEmpty &&
        !purchaseSuppliers.any((supplier) => supplier.id == supplierId)) {
      supplierId =
          purchaseSuppliers.isNotEmpty ? purchaseSuppliers.first.id : '';
      supplierName =
          purchaseSuppliers.isNotEmpty ? purchaseSuppliers.first.name : '';
    }
    Product? selectedProduct;
    ProductSaleUnit? selectedUnit;
    DateTime? selectedExpiryDate;
    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController();
    final productSearchController = TextEditingController();
    final paidAmountController = TextEditingController();
    final dialogShortcutFocusNode = FocusNode();
    final productSearchFocusNode = FocusNode();
    final qtyFocusNode = FocusNode();
    final costFocusNode = FocusNode();
    final addLineFocusNode = FocusNode();
    final paidAmountFocusNode = FocusNode();
    var productSearchFocusRequested = false;
    String paymentStatus = source?.paymentStatus ?? 'paid';
    String paymentMethod = source?.paymentMethod ?? 'Cash';
    final editingReceivedPurchase = editPurchase?.isReceived == true;
    final editingReturnedPurchase = editPurchase?.isReturned == true;
    final editingPostedPurchase =
        editingReceivedPurchase || editingReturnedPurchase;
    final sourceCurrency = items
        .map((item) => item.unitCostCurrency.trim().toUpperCase())
        .firstWhere(
          (currency) => currency == 'USD' || currency == 'LBP',
          orElse: () => '',
        );
    String costCurrency = sourceCurrency.isEmpty
        ? widget.store.runtime.profile.defaultProductCurrency
        : sourceCurrency;
    bool receiveNow = editingPostedPurchase;

    var isClosingPurchaseDialog = false;

    dynamic activePurchaseDialogContext;
    StateSetter? activePurchaseDialogSetState;

    final purchaseDialogSession = _PurchaseDialogSession(
      widget: widget,
      pageState: this,
      context: context,
      isMounted: () => mounted,
      stateSet: setState,
      tr: tr,
      formKey: formKey,
      source: source,
      items: items,
      sqliteProducts: sqliteProducts,
      sqliteSuppliers: sqliteSuppliers,
      purchaseProducts: purchaseProducts,
      purchaseSuppliers: purchaseSuppliers,
      supplierId: supplierId,
      supplierName: supplierName,
      initialWarehouse: initialWarehouse,
      selectedWarehouseId: selectedWarehouseId,
      selectedWarehouseName: selectedWarehouseName,
      selectedProduct: selectedProduct,
      selectedUnit: selectedUnit,
      selectedExpiryDate: selectedExpiryDate,
      qtyController: qtyController,
      costController: costController,
      productSearchController: productSearchController,
      paidAmountController: paidAmountController,
      dialogShortcutFocusNode: dialogShortcutFocusNode,
      productSearchFocusNode: productSearchFocusNode,
      qtyFocusNode: qtyFocusNode,
      costFocusNode: costFocusNode,
      addLineFocusNode: addLineFocusNode,
      paidAmountFocusNode: paidAmountFocusNode,
      productSearchFocusRequested: productSearchFocusRequested,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      editingReceivedPurchase: editingReceivedPurchase,
      editingReturnedPurchase: editingReturnedPurchase,
      editingPostedPurchase: editingPostedPurchase,
      sourceCurrency: sourceCurrency,
      costCurrency: costCurrency,
      receiveNow: receiveNow,
      isClosingPurchaseDialog: isClosingPurchaseDialog,
      activePurchaseDialogContext: activePurchaseDialogContext,
      activePurchaseDialogSetState: activePurchaseDialogSetState,
      template: template,
      editPurchase: editPurchase,
    );
    purchaseDialogSession.applySuggestedSupplierPrice();
    await purchaseDialogSession.showPurchaseDialog();
  }
}
