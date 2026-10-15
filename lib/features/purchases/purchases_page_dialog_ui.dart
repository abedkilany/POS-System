part of 'purchases_page.dart';

extension _PurchaseDialogSessionUi on _PurchaseDialogSession {
  Future<void> showPurchaseDialog() async {
    if (!context.mounted) return;
    HardwareKeyboard.instance
        .addHandler(handlePurchaseDialogHardwareShortcut);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        isDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            activePurchaseDialogContext = dialogContext;
            activePurchaseDialogSetState = setDialogState;
            final total =
                items.fold<double>(0, (sum, item) => sum + item.lineTotal);
            final units = selectedProduct?.effectivePurchaseUnits ??
                const <ProductSaleUnit>[];
            if (selectedUnit != null &&
                !units.any((unit) => unit.id == selectedUnit!.id)) {
              selectedUnit = units.isNotEmpty ? units.first : null;
              applySuggestedSupplierPrice();
            }
            final dialogWidth = VentioResponsive.modalMaxWidth(context, 1220);
            final dialogHeight = MediaQuery.sizeOf(context).height * 0.88;
            return CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    cancelPurchaseDialog(dialogContext),
              },
              child: Focus(
                focusNode: dialogShortcutFocusNode,
                autofocus: true,
                onKeyEvent: (node, event) => handlePurchaseDialogShortcutKey(
                    event, dialogContext, setDialogState),
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: dialogWidth, maxHeight: dialogHeight),
                      child: Material(
                        clipBehavior: Clip.antiAlias,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 20, 16, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(
                                          template == null
                                              ? tr.text('new_purchase')
                                              : tr.text(
                                                  'duplicate_purchase_draft'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall)),
                                  IconButton(
                                    tooltip: tr.text('cancel'),
                                    onPressed: () =>
                                        cancelPurchaseDialog(dialogContext),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                              child: _buildPurchaseDialogShortcutGuide(
                                  context, tr),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: SingleChildScrollView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: EdgeInsets.all(
                                    VentioResponsive.pagePadding(context)),
                                child: Form(
                                  key: formKey,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final desktopLayout =
                                          constraints.maxWidth >= 900;
                                      final gap = VentioResponsive.gap(context);

                                      Widget sectionCard(
                                          {required String title,
                                          required IconData icon,
                                          required List<Widget> children}) {
                                        return Card(
                                          elevation: 0,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.35),
                                          child: Padding(
                                            padding:
                                                VentioResponsive.cardInsets(
                                                    context),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(icon, size: 20),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                        child: Text(title,
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .titleMedium)),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                ...children,
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      Widget supplierSection() {
                                        return sectionCard(
                                          title: tr.text('purchase_details'),
                                          icon: Icons.receipt_long_outlined,
                                          children: [
                                            if (purchaseProducts.isEmpty) ...[
                                              Text(tr.text(
                                                  'no_stock_tracked_products')),
                                              SizedBox(height: gap),
                                            ],
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child:
                                                      DropdownButtonFormField<
                                                          String>(
                                                    initialValue:
                                                        supplierId.isEmpty
                                                            ? null
                                                            : supplierId,
                                                    decoration: InputDecoration(
                                                        labelText: tr
                                                            .text('supplier')),
                                                    items: purchaseSuppliers
                                                        .map((supplier) =>
                                                            DropdownMenuItem(
                                                                value:
                                                                    supplier.id,
                                                                child: Text(
                                                                    supplier
                                                                        .name)))
                                                        .toList(),
                                                    onChanged: (value) {
                                                      final matches =
                                                          purchaseSuppliers
                                                              .where((s) =>
                                                                  s.id == value)
                                                              .toList();
                                                      final supplier =
                                                          matches.isEmpty
                                                              ? null
                                                              : matches.first;
                                                      supplierId =
                                                          supplier?.id ?? '';
                                                      supplierName =
                                                          supplier?.name ?? '';
                                                      applySuggestedSupplierPrice();
                                                      setDialogState(() {});
                                                    },
                                                    validator: (_) => supplierId
                                                            .isEmpty
                                                        ? tr.text(
                                                            'supplier_required')
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton.filledTonal(
                                                  tooltip:
                                                      tr.text('add_supplier'),
                                                  onPressed: () =>
                                                      createQuickSupplier(
                                                          setDialogState),
                                                  icon: const Icon(Icons
                                                      .person_add_alt_1_outlined),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            DropdownButtonFormField<String>(
                                              initialValue: selectedWarehouseId,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      tr.text('warehouse')),
                                              items: widget.store.warehouses
                                                  .map(
                                                    (warehouse) =>
                                                        DropdownMenuItem<
                                                            String>(
                                                      value: warehouse.id,
                                                      child:
                                                          Text(warehouse.name),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                final selected = widget.store
                                                    .resolveWarehouseForPurchase(
                                                  warehouseId: value ?? '',
                                                );
                                                selectedWarehouseId =
                                                    selected.id;
                                                selectedWarehouseName =
                                                    selected.name;
                                                setDialogState(() {});
                                              },
                                              validator: (_) =>
                                                  selectedWarehouseId.isEmpty
                                                      ? tr.text(
                                                          'warehouse_required')
                                                      : null,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${tr.text('warehouse')}: ${selectedWarehouseName.isEmpty ? selectedWarehouseId : selectedWarehouseName}',
                                            ),
                                            SizedBox(height: gap),
                                            DropdownButtonFormField<String>(
                                              initialValue: costCurrency,
                                              decoration: InputDecoration(
                                                labelText: tr.text('currency'),
                                                helperText: tr.text(
                                                    'purchase_currency_helper'),
                                              ),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 'USD',
                                                  child: Text('USD'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 'LBP',
                                                  child: Text('LBP'),
                                                ),
                                              ],
                                              onChanged: items.isNotEmpty
                                                  ? null
                                                  : (value) {
                                                      costCurrency =
                                                          value ?? 'USD';
                                                      applySuggestedSupplierPrice();
                                                      setDialogState(() {});
                                                    },
                                            ),
                                            SizedBox(height: gap),
                                            SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: receiveNow,
                                              onChanged: editingPostedPurchase
                                                  ? null
                                                  : (value) => setDialogState(
                                                      () => receiveNow = value),
                                              title:
                                                  Text(tr.text('receive_now')),
                                              subtitle: Text(
                                                  tr.text('receive_now_desc')),
                                            ),
                                            const SizedBox(height: 8),
                                            DropdownButtonFormField<String>(
                                              initialValue: paymentStatus,
                                              decoration: InputDecoration(
                                                  labelText: tr
                                                      .text('payment_status')),
                                              items: [
                                                DropdownMenuItem(
                                                    value: 'paid',
                                                    child: Text(
                                                        tr.text('cash_paid'))),
                                                DropdownMenuItem(
                                                    value: 'credit',
                                                    child: Text(tr.text(
                                                        'credit_unpaid'))),
                                                DropdownMenuItem(
                                                    value: 'partial',
                                                    child: Text(tr.text(
                                                        'partial_payment'))),
                                              ],
                                              onChanged: editingPostedPurchase
                                                  ? null
                                                  : (value) => setDialogState(
                                                      () => paymentStatus =
                                                          value ?? 'paid'),
                                            ),
                                            if (!editingPostedPurchase &&
                                                paymentStatus != 'credit') ...[
                                              const SizedBox(height: 8),
                                              DropdownButtonFormField<String>(
                                                initialValue: paymentMethod,
                                                decoration: InputDecoration(
                                                    labelText: tr.text(
                                                        'payment_method')),
                                                items: [
                                                  DropdownMenuItem(
                                                      value: 'Cash',
                                                      child: Text(tr.text(
                                                          'payment_cash'))),
                                                  DropdownMenuItem(
                                                      value: 'Card',
                                                      child: Text(tr.text(
                                                          'payment_card'))),
                                                  DropdownMenuItem(
                                                      value: 'Wish',
                                                      child: Text(tr.text(
                                                          'payment_wish'))),
                                                  DropdownMenuItem(
                                                      value: 'Check',
                                                      child: Text(tr.text(
                                                          'payment_check'))),
                                                ],
                                                onChanged: (value) =>
                                                    setDialogState(() =>
                                                        paymentMethod =
                                                            value ?? 'Cash'),
                                              ),
                                            ],
                                            if (!editingPostedPurchase &&
                                                paymentStatus == 'partial') ...[
                                              SizedBox(height: gap),
                                              TextFormField(
                                                controller:
                                                    paidAmountController,
                                                focusNode: paidAmountFocusNode,
                                                decoration: InputDecoration(
                                                    labelText:
                                                        tr.text('paid_amount')),
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                Chip(
                                                    label: Text(
                                                        '${tr.text('status')}: ${editingReturnedPurchase ? tr.text('returned') : receiveNow ? tr.text('received') : tr.text('draft')}')),
                                                Chip(
                                                    label: Text(
                                                        '${tr.text('items')}: ${items.length}')),
                                              ],
                                            ),
                                          ],
                                        );
                                      }

                                      Widget productEntrySection() {
                                        if (!productSearchFocusRequested) {
                                          productSearchFocusRequested = true;
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            productSearchFocusNode
                                                .requestFocus();
                                          });
                                        }
                                        final conversion =
                                            selectedUnitConversionSummary();
                                        final selectedProductTitle =
                                            selectedProduct?.name ??
                                                tr.text('product');
                                        final selectedProductSubtitle =
                                            selectedProduct == null
                                                ? tr.text(
                                                    'scan_purchase_barcode_hint')
                                                : [
                                                    if (selectedProduct!.code
                                                        .trim()
                                                        .isNotEmpty)
                                                      selectedProduct!.code
                                                          .trim(),
                                                    if (selectedProduct!.barcode
                                                        .trim()
                                                        .isNotEmpty)
                                                      selectedProduct!.barcode
                                                          .trim(),
                                                    '${tr.text('stock')}: ${_formatQuantity(widget.store.stockForWarehouse(selectedProduct!.id, selectedWarehouseId))}',
                                                  ].join(' • ');
                                        return sectionCard(
                                          title: tr.text('add_product'),
                                          icon: Icons.add_box_outlined,
                                          children: [
                                            Focus(
                                              focusNode: productSearchFocusNode,
                                              onKeyEvent: (node, event) {
                                                if (event is KeyDownEvent &&
                                                    event.logicalKey ==
                                                        LogicalKeyboardKey
                                                            .enter) {
                                                  choosePurchaseProduct(
                                                      setDialogState);
                                                  return KeyEventResult.handled;
                                                }
                                                return KeyEventResult.ignored;
                                              },
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                onTap: () =>
                                                    choosePurchaseProduct(
                                                        setDialogState),
                                                child: InputDecorator(
                                                  decoration: InputDecoration(
                                                    labelText: tr
                                                        .text('search_product'),
                                                    prefixIcon: const Icon(
                                                        Icons.search),
                                                    suffixIcon: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          tooltip: tr.text(
                                                              'scan_with_camera'),
                                                          onPressed: () =>
                                                              choosePurchaseProduct(
                                                                  setDialogState,
                                                                  scanFirst:
                                                                      true),
                                                          icon: const Icon(Icons
                                                              .camera_alt_outlined),
                                                        ),
                                                        IconButton(
                                                          tooltip: tr.text(
                                                              'add_product'),
                                                          onPressed: () =>
                                                              createQuickProduct(
                                                                  setDialogState),
                                                          icon: const Icon(Icons
                                                              .add_box_outlined),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(selectedProductTitle,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                      if (selectedProductSubtitle
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          selectedProductSubtitle,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: gap),
                                            LayoutBuilder(
                                              builder:
                                                  (context, fieldConstraints) {
                                                final oneColumn =
                                                    fieldConstraints.maxWidth <
                                                        520;
                                                final unitField =
                                                    DropdownButtonFormField<
                                                        String>(
                                                  initialValue:
                                                      selectedUnit?.id,
                                                  decoration: InputDecoration(
                                                      labelText: tr.text(
                                                          'purchase_unit')),
                                                  items: units
                                                      .map((unit) =>
                                                          DropdownMenuItem(
                                                              value: unit.id,
                                                              child: Text(
                                                                  '${unit.name} × ${_formatQuantity(unit.conversionToBase)}')))
                                                      .toList(),
                                                  onChanged: (value) {
                                                    final matches = units
                                                        .where((unit) =>
                                                            unit.id == value)
                                                        .toList();
                                                    selectedUnit =
                                                        matches.isEmpty
                                                            ? null
                                                            : matches.first;
                                                    applySuggestedSupplierPrice();
                                                    setDialogState(() {});
                                                  },
                                                );
                                                final qtyField = TextFormField(
                                                  controller: qtyController,
                                                  focusNode: qtyFocusNode,
                                                  decoration: InputDecoration(
                                                      labelText:
                                                          tr.text('quantity')),
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  onFieldSubmitted: (_) =>
                                                      costFocusNode
                                                          .requestFocus(),
                                                  onChanged: (_) =>
                                                      setDialogState(() {}),
                                                );
                                                final costField = TextFormField(
                                                  controller: costController,
                                                  focusNode: costFocusNode,
                                                  decoration: InputDecoration(
                                                      labelText:
                                                          tr.text('unit_cost'),
                                                      helperText:
                                                          priceHintForSelectedProduct()
                                                                  .isEmpty
                                                              ? null
                                                              : priceHintForSelectedProduct()),
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  onFieldSubmitted: (_) =>
                                                      addLineFocusNode
                                                          .requestFocus(),
                                                );
                                                final expiryEnabled =
                                                    selectedProduct
                                                            ?.expiryTrackingEnabled ==
                                                        true;
                                                final expiryField =
                                                    OutlinedButton.icon(
                                                  icon: const Icon(
                                                      Icons.event_outlined),
                                                  onPressed: !expiryEnabled
                                                      ? null
                                                      : () async {
                                                          final picked =
                                                              await showDatePicker(
                                                            context:
                                                                dialogContext,
                                                            initialDate:
                                                                selectedExpiryDate ??
                                                                    DateTime
                                                                        .now(),
                                                            firstDate:
                                                                DateTime.now(),
                                                            lastDate: DateTime
                                                                    .now()
                                                                .add(const Duration(
                                                                    days:
                                                                        36500)),
                                                          );
                                                          if (picked != null) {
                                                            setDialogState(() =>
                                                                selectedExpiryDate =
                                                                    picked);
                                                          }
                                                        },
                                                  label: Text(!expiryEnabled
                                                      ? '${tr.text('expiration_date')} — ${tr.text('disabled')}'
                                                      : selectedExpiryDate ==
                                                              null
                                                          ? '${tr.text('expiration_date')} *'
                                                          : MaterialLocalizations.of(
                                                                  dialogContext)
                                                              .formatMediumDate(
                                                                  selectedExpiryDate!)),
                                                );
                                                if (oneColumn) {
                                                  return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      unitField,
                                                      SizedBox(height: gap),
                                                      qtyField,
                                                      SizedBox(height: gap),
                                                      costField,
                                                      SizedBox(height: gap),
                                                      expiryField,
                                                    ],
                                                  );
                                                }
                                                return Wrap(
                                                  spacing: 12,
                                                  runSpacing: 12,
                                                  children: [
                                                    SizedBox(
                                                        width: 220,
                                                        child: unitField),
                                                    SizedBox(
                                                        width: 120,
                                                        child: qtyField),
                                                    SizedBox(
                                                        width: 190,
                                                        child: costField),
                                                    SizedBox(
                                                        width: 220,
                                                        child: expiryField),
                                                  ],
                                                );
                                              },
                                            ),
                                            if (conversion.isNotEmpty) ...[
                                              SizedBox(height: gap),
                                              Align(
                                                  alignment:
                                                      AlignmentDirectional
                                                          .centerStart,
                                                  child: Chip(
                                                      avatar: const Icon(
                                                          Icons.compare_arrows,
                                                          size: 18),
                                                      label: Text(conversion))),
                                            ],
                                            SizedBox(height: gap),
                                            Focus(
                                              focusNode: addLineFocusNode,
                                              onKeyEvent: (node, event) {
                                                if (event is KeyDownEvent &&
                                                    event.logicalKey ==
                                                        LogicalKeyboardKey
                                                            .enter) {
                                                  addSelectedPurchaseLine(
                                                      setDialogState);
                                                  return KeyEventResult.handled;
                                                }
                                                return KeyEventResult.ignored;
                                              },
                                              child: FilledButton.icon(
                                                onPressed: selectedProduct ==
                                                            null ||
                                                        selectedUnit == null
                                                    ? null
                                                    : () =>
                                                        addSelectedPurchaseLine(
                                                            setDialogState),
                                                icon: const Icon(Icons.add),
                                                label: Text(tr.text(
                                                    'add_product_to_purchase')),
                                              ),
                                            ),
                                          ],
                                        );
                                      }

                                      Widget lineActions(PurchaseItem item) =>
                                          Wrap(
                                            spacing: 4,
                                            children: [
                                              IconButton(
                                                  icon: const Icon(
                                                      Icons.edit_outlined),
                                                  tooltip: tr.text('edit'),
                                                  onPressed: () =>
                                                      editPurchaseLine(
                                                        item,
                                                        setDialogState,
                                                        dialogContext,
                                                      )),
                                              IconButton(
                                                  icon: const Icon(
                                                      Icons.delete_outline),
                                                  tooltip: tr.text('delete'),
                                                  onPressed: () =>
                                                      setDialogState(() =>
                                                          items.remove(item))),
                                            ],
                                          );

                                      Widget purchaseLinesSection() {
                                        if (items.isEmpty) {
                                          return sectionCard(
                                            title: tr.text('purchase_invoice'),
                                            icon: Icons.table_chart_outlined,
                                            children: [
                                              Text(tr.text('no_items_added'))
                                            ],
                                          );
                                        }
                                        final table = SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            columns: [
                                              DataColumn(
                                                  label:
                                                      Text(tr.text('product'))),
                                              DataColumn(
                                                  label: Text(tr.text('unit'))),
                                              DataColumn(
                                                  label: Text(
                                                      tr.text('quantity'))),
                                              DataColumn(
                                                  label: Text(
                                                      tr.text('unit_cost'))),
                                              DataColumn(
                                                  label:
                                                      Text(tr.text('total'))),
                                              DataColumn(
                                                  label:
                                                      Text(tr.text('actions'))),
                                            ],
                                            rows: items
                                                .map((item) => DataRow(cells: [
                                                      DataCell(SizedBox(
                                                          width: 180,
                                                          child: Text(
                                                              item.productName,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis))),
                                                      DataCell(Text(item
                                                          .purchaseUnitName)),
                                                      DataCell(Text(
                                                          _formatQuantity(
                                                              item.quantity))),
                                                      DataCell(Text(formatCurrency(
                                                          item.originalUnitCost ??
                                                              item.unitCost,
                                                          currency: item
                                                              .unitCostCurrency))),
                                                      DataCell(Text(
                                                          formatUsdReferenceAmount(
                                                              item.lineTotal,
                                                              widget.store
                                                                  .storeProfile))),
                                                      DataCell(
                                                          lineActions(item)),
                                                    ]))
                                                .toList(),
                                          ),
                                        );
                                        final cards = Column(
                                          children: items
                                              .map((item) => Card(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            bottom: 8),
                                                    child: ListTile(
                                                      title: Text(
                                                          item.productName),
                                                      subtitle: Text(
                                                          '${unitConversionSummary(item)} • ${formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency)} • ${formatUsdReferenceAmount(item.lineTotal, widget.store.storeProfile)}'),
                                                      trailing:
                                                          lineActions(item),
                                                    ),
                                                  ))
                                              .toList(),
                                        );
                                        return sectionCard(
                                          title: tr.text('purchase_invoice'),
                                          icon: Icons.table_chart_outlined,
                                          children: [
                                            desktopLayout ? table : cards
                                          ],
                                        );
                                      }

                                      Widget summarySection() {
                                        return Card(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                          child: Padding(
                                            padding:
                                                VentioResponsive.cardInsets(
                                                    context),
                                            child: Wrap(
                                              spacing: 20,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                    '${tr.text('supplier')}: ${supplierName.isEmpty ? '-' : supplierName}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium),
                                                Text(
                                                    '${tr.text('items')}: ${items.length}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium),
                                                Text(
                                                    '${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      final leftPanel = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          supplierSection(),
                                          SizedBox(height: gap),
                                          productEntrySection()
                                        ],
                                      );
                                      final rightPanel = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          purchaseLinesSection(),
                                          SizedBox(height: gap),
                                          summarySection()
                                        ],
                                      );

                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (desktopLayout)
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                    width: 390,
                                                    child: leftPanel),
                                                SizedBox(width: gap),
                                                Expanded(child: rightPanel),
                                              ],
                                            )
                                          else ...[
                                            leftPanel,
                                            SizedBox(height: gap),
                                            rightPanel,
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                VentioResponsive.pagePadding(context),
                                12,
                                VentioResponsive.pagePadding(context),
                                16,
                              ),
                              child: LayoutBuilder(
                                builder: (context, footerConstraints) {
                                  final compactFooter =
                                      footerConstraints.maxWidth < 520;
                                  final totalText = Text(
                                    '${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  );
                                  final cancelButton = TextButton(
                                    onPressed: () =>
                                        cancelPurchaseDialog(dialogContext),
                                    child: Text(tr.text('cancel')),
                                  );
                                  final saveButton = FilledButton.icon(
                                    onPressed: items.isEmpty
                                        ? null
                                        : () => savePurchaseFromDialog(
                                            dialogContext),
                                    icon: const Icon(Icons.save_outlined),
                                    label: Text(tr.text('save')),
                                  );
                                  if (compactFooter) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        totalText,
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(child: cancelButton),
                                            const SizedBox(width: 12),
                                            Expanded(child: saveButton),
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: totalText),
                                      cancelButton,
                                      const SizedBox(width: 12),
                                      saveButton,
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      HardwareKeyboard.instance
          .removeHandler(handlePurchaseDialogHardwareShortcut);
      activePurchaseDialogContext = null;
      activePurchaseDialogSetState = null;
    }
    qtyController.dispose();
    costController.dispose();
    productSearchController.dispose();
    paidAmountController.dispose();
    dialogShortcutFocusNode.dispose();
    productSearchFocusNode.dispose();
    qtyFocusNode.dispose();
    costFocusNode.dispose();
    addLineFocusNode.dispose();
    paidAmountFocusNode.dispose();
  }
}
