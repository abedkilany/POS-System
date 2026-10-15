// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPagePostedSaleEdit on _SalesPageState {
  String _saleReturnLabel(AppLocalizations tr) {
    switch (tr.locale.languageCode) {
      case 'ar':
        return 'مرتجع الفاتورة';
      case 'fr':
        return 'Retour de facture';
      default:
        return 'Return invoice';
    }
  }

  Future<void> _editPostedSale(BuildContext sheetContext, Sale sale) async {
    if (!widget.store.security.hasPermission(AppPermission.salesEdit) ||
        sale.isCancelled) {
      return;
    }
    final tr = AppLocalizations.of(sheetContext);
    final activeProducts = widget.store.catalog.products
        .where((product) => product.isActive && !product.isDeleted)
        .toList(growable: true);
    final lines = <_PostedSaleEditLine>[];
    for (final item in sale.items) {
      Product? product;
      for (final candidate in widget.store.catalog.products) {
        if (candidate.id == item.productId) {
          product = candidate;
          break;
        }
      }
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr.format(
                'product_not_found_named', {'product': item.productName}))));
        return;
      }
      if (!activeProducts.any((candidate) => candidate.id == product!.id)) {
        activeProducts.add(product);
      }
      lines.add(_PostedSaleEditLine(
          product: product,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          unitName: item.unitName.trim().isEmpty ? product.unit : item.unitName,
          conversionToBase:
              item.conversionToBase <= 0 ? 1 : item.conversionToBase));
    }
    if (activeProducts.isEmpty) return;
    final customerIds = <String>{AppStore.walkInCustomerId};
    customerIds.addAll(widget.store.commerce.customers
        .where((customer) => !customer.isDeleted)
        .map((customer) => customer.id));
    if (sale.customerId.trim().isNotEmpty) customerIds.add(sale.customerId);
    var selectedCustomerId = customerIds.contains(sale.customerId)
        ? sale.customerId
        : AppStore.walkInCustomerId;
    final warehouses = widget.store.inventory.warehouses
        .where((warehouse) => warehouse.isActive && !warehouse.isDeleted)
        .toList(growable: true);
    for (final warehouse in widget.store.inventory.warehouses) {
      if (warehouse.id == sale.warehouseId &&
          !warehouses.any((item) => item.id == warehouse.id)) {
        warehouses.add(warehouse);
        break;
      }
    }
    var selectedWarehouseId = warehouses.any((w) => w.id == sale.warehouseId)
        ? sale.warehouseId
        : widget.store.inventory
            .resolveWarehouseForSale(warehouseId: sale.warehouseId)
            .id;
    final discountController =
        TextEditingController(text: _formatMoneyInput(sale.discount));
    var saving = false;
    final edited = await showDialog<Sale>(
        context: sheetContext,
        barrierDismissible: false,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (context, setDialogState) {
              Future<void> save() async {
                if (saving || lines.isEmpty) return;
                final discount =
                    double.tryParse(discountController.text.trim()) ?? 0.0;
                final subtotal = lines.fold<double>(
                    0, (sum, line) => sum + (line.quantity * line.unitPrice));
                if (discount < 0 || discount > subtotal + 0.000001) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                      content: Text(tr.text('discount_exceeds_subtotal'))));
                  return;
                }
                for (final line in lines) {
                  if (line.quantity <= 0 || line.unitPrice < 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                        content: Text(tr.text('invalid_sale_item_values'))));
                    return;
                  }
                }
                setDialogState(() => saving = true);
                try {
                  final warehouse = widget.store.inventory
                      .resolveWarehouseForSale(
                          warehouseId: selectedWarehouseId);
                  final result = await widget.store.commerce.editPostedSale(
                      saleId: sale.id,
                      expectedVersion: sale.version,
                      customerId: selectedCustomerId,
                      customerName: selectedCustomerId == sale.customerId
                          ? sale.customerName
                          : widget.store
                              .commerce.resolveCustomerName(selectedCustomerId),
                      items: lines
                          .map((line) => SaleItem(
                              productId: line.product.id,
                              productName: line.product.name,
                              unitPrice: line.unitPrice,
                              quantity: line.quantity,
                              unitName: line.unitName,
                              baseQuantity:
                                  line.quantity * line.conversionToBase,
                              conversionToBase: line.conversionToBase,
                              unitCost: 0))
                          .toList(growable: false),
                      discount: discount,
                      originalDiscount: discount,
                      discountCurrency: sale.discountCurrency,
                      discountExchangeRateAtEntry:
                          sale.discountExchangeRateAtEntry,
                      warehouseId: selectedWarehouseId,
                      warehouseName: warehouse.name);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(result);
                  }
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() => saving = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(localizedErrorText(tr, error))));
                }
              }

              return AlertDialog(
                  title: Text(tr.text('edit_sale')),
                  content: SizedBox(
                      width: math.min(
                          MediaQuery.sizeOf(context).width * 0.92, 760.0),
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * 0.72),
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                DropdownButtonFormField<String>(
                                    initialValue: selectedCustomerId,
                                    decoration: InputDecoration(
                                        labelText: tr.text('customer')),
                                    items: customerIds
                                        .map((id) => DropdownMenuItem<String>(
                                            value: id,
                                            child: Text(id == sale.customerId
                                                ? sale.customerName
                                                : widget.store
                                                    .commerce.resolveCustomerName(id))))
                                        .toList(growable: false),
                                    onChanged: saving
                                        ? null
                                        : (value) => setDialogState(() {
                                              if (value != null) {
                                                selectedCustomerId = value;
                                              }
                                            })),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                    initialValue: selectedWarehouseId,
                                    decoration: InputDecoration(
                                        labelText: tr.text('warehouse')),
                                    items: warehouses
                                        .map((warehouse) =>
                                            DropdownMenuItem<String>(
                                                value: warehouse.id,
                                                child: Text(warehouse.name)))
                                        .toList(growable: false),
                                    onChanged: saving
                                        ? null
                                        : (value) => setDialogState(() {
                                              if (value != null) {
                                                selectedWarehouseId = value;
                                              }
                                            })),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: discountController,
                                    enabled: !saving,
                                    decoration: InputDecoration(
                                        labelText: tr.text('discount')),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true)),
                                const SizedBox(height: 16),
                                ...List.generate(lines.length, (index) {
                                  final line = lines[index];
                                  return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(children: [
                                            Row(children: [
                                              Expanded(
                                                  child: DropdownButtonFormField<
                                                          String>(
                                                      initialValue:
                                                          line.product.id,
                                                      isExpanded: true,
                                                      decoration: InputDecoration(
                                                          labelText: tr
                                                              .text('product')),
                                                      items: activeProducts
                                                          .map((product) => DropdownMenuItem<
                                                                  String>(
                                                              value: product.id,
                                                              child: Text(
                                                                  product.name,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis)))
                                                          .toList(
                                                              growable: false),
                                                      onChanged: saving
                                                          ? null
                                                          : (value) =>
                                                              setDialogState(() {
                                                                if (value ==
                                                                    null) {
                                                                  return;
                                                                }
                                                                final product =
                                                                    activeProducts.firstWhere(
                                                                        (item) =>
                                                                            item.id ==
                                                                            value);
                                                                final unit = product
                                                                    .effectiveSaleUnits
                                                                    .first;
                                                                line.product =
                                                                    product;
                                                                line.unitName =
                                                                    unit.name;
                                                                line.conversionToBase =
                                                                    unit.conversionToBase;
                                                                line.unitPrice =
                                                                    unit.price > 0
                                                                        ? unit
                                                                            .price
                                                                        : product
                                                                            .price;
                                                              }))),
                                              IconButton(
                                                  tooltip: tr.text('remove'),
                                                  onPressed: saving ||
                                                          lines.length == 1
                                                      ? null
                                                      : () => setDialogState(
                                                          () => lines
                                                              .removeAt(index)),
                                                  icon: const Icon(
                                                      Icons.delete_outline))
                                            ]),
                                            const SizedBox(height: 8),
                                            Row(children: [
                                              Expanded(
                                                  child: TextFormField(
                                                      key: ValueKey(
                                                          'sale-edit-qty-$index-${line.product.id}'),
                                                      initialValue:
                                                          _formatQuantity(
                                                              line.quantity),
                                                      enabled: !saving,
                                                      decoration:
                                                          InputDecoration(
                                                              labelText: tr.text(
                                                                  'quantity')),
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                              decimal: true),
                                                      onChanged: (value) => line
                                                              .quantity =
                                                          double.tryParse(value) ??
                                                              0)),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: TextFormField(
                                                      key: ValueKey(
                                                          'sale-edit-price-$index-${line.product.id}'),
                                                      initialValue:
                                                          _formatMoneyInput(
                                                              line.unitPrice),
                                                      enabled: !saving,
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              tr.text('price')),
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                              decimal: true),
                                                      onChanged: (value) =>
                                                          line.unitPrice =
                                                              double.tryParse(
                                                                      value) ??
                                                                  0))
                                            ])
                                          ])));
                                }),
                                Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                        onPressed: saving
                                            ? null
                                            : () => setDialogState(() {
                                                  final product =
                                                      activeProducts.first;
                                                  final unit = product
                                                      .effectiveSaleUnits.first;
                                                  lines.add(_PostedSaleEditLine(
                                                      product: product,
                                                      quantity: 1,
                                                      unitPrice: unit.price > 0
                                                          ? unit.price
                                                          : product.price,
                                                      unitName: unit.name,
                                                      conversionToBase: unit
                                                          .conversionToBase));
                                                }),
                                        icon: const Icon(Icons.add),
                                        label: Text(tr.text('add_product'))))
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: Text(tr.text('cancel'))),
                    FilledButton.icon(
                        key: const ValueKey('SalesEditSaveButton'),
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(tr.text('save')))
                  ]);
            }));
    discountController.dispose();
    if (edited == null || !mounted) return;
    setState(() {
      _salesQueryFuture = null;
      _salesQueryFutureKey = '';
      _invoiceDetailsFutureById.remove(sale.id);
      _invoiceSearchIndexCache.invalidate();
    });
    if (sheetContext.mounted) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text(tr.text('invoice_edited_successfully'))));
    }
  }

  CreditNote? _latestActiveCreditNoteForSale(String saleId) {
    final notes = widget.store.commerce.creditNotes
        .where((note) =>
            note.originalSaleId == saleId &&
            !<String>{'cancelled', 'reversed', 'void'}
                .contains(note.status.trim().toLowerCase()))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return notes.isEmpty ? null : notes.last;
  }
}
