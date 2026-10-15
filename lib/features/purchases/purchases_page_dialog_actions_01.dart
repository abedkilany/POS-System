part of 'purchases_page.dart';

extension _PurchaseDialogSessionActions1 on _PurchaseDialogSession {
  SupplierProductPrice? selectedSupplierPriceFor(Product product) {
    return supplierId.isEmpty
        ? null
        : widget.store.supplierProductPriceFor(
            productId: product.id, supplierId: supplierId);
  }

  PurchaseItem? suggestedPurchaseItem(Product product) {
    return supplierId.isEmpty
        ? null
        : widget.store
            .lastPurchaseItemFor(productId: product.id, supplierId: supplierId);
  }

  double suggestedBaseCost(Product product) {
    final supplierPrice = selectedSupplierPriceFor(product);
    if (supplierPrice != null) {
      return toUsdReferencePrice(supplierPrice.cost, supplierPrice.currency,
          widget.store.storeProfile);
    }
    return suggestedPurchaseItem(product)?.unitCostPerBase ??
        widget.store.lastPurchasePriceForProduct(product.id) ??
        product.usdCost;
  }

  void applySuggestedSupplierPrice() {
    final product = selectedProduct;
    final unit = selectedUnit;
    if (product == null || unit == null) {
      costController.text = '0';
      return;
    }
    final displayCost = fromUsdReferencePrice(
        suggestedBaseCost(product) * unit.conversionToBase,
        costCurrency,
        widget.store.storeProfile);
    costController.text =
        displayCost.toStringAsFixed(costCurrency == 'LBP' ? 0 : 2);
  }

  String priceHintForSelectedProduct() {
    final product = selectedProduct;
    if (product == null) return '';
    final configuredSupplierPrice = supplierId.isEmpty
        ? null
        : widget.store.supplierProductPriceFor(
            productId: product.id, supplierId: supplierId);
    final supplierPrice = supplierId.isEmpty
        ? null
        : widget.store.lastPurchasePriceFor(
            productId: product.id, supplierId: supplierId);
    final lastGeneral = widget.store.lastPurchasePriceForProduct(product.id);
    final avg = widget.store.averagePurchaseCostForProduct(product.id);
    final supplierCount = widget.store.supplierCountForProduct(product.id);
    final parts = <String>[];
    if (configuredSupplierPrice != null) {
      parts.add(
          '${tr.text('supplier_price')}: ${formatCurrency(configuredSupplierPrice.cost, currency: configuredSupplierPrice.currency)}');
    }
    if (supplierPrice != null) {
      parts.add(
          '${tr.text('supplier_last_base')}: ${formatUsdReferenceAmount(supplierPrice, widget.store.storeProfile)}');
    }
    if (lastGeneral != null) {
      parts.add(
          '${tr.text('last_base')}: ${formatUsdReferenceAmount(lastGeneral, widget.store.storeProfile)}');
    }
    if (avg > 0) {
      parts.add(
          '${tr.text('avg_base')}: ${formatUsdReferenceAmount(avg, widget.store.storeProfile)}');
    }
    if (supplierCount > 0) {
      parts.add(
          '$supplierCount ${tr.text(supplierCount == 1 ? 'supplier' : 'suppliers')}');
    }
    return parts.join(' • ');
  }

  String unitConversionSummary(PurchaseItem item) {
    final unitName =
        item.purchaseUnitName.isEmpty ? tr.text('unit') : item.purchaseUnitName;
    return '${_formatQuantity(item.quantity)} $unitName = ${_formatQuantity(item.baseQuantity)} ${tr.text('base')} ${tr.text(item.baseQuantity == 1 ? 'unit' : 'units')}';
  }

  String selectedUnitConversionSummary() {
    final unit = selectedUnit;
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    if (unit == null || qty <= 0) return '';
    return '${_formatQuantity(qty)} ${unit.name} = ${_formatQuantity(qty * unit.conversionToBase)} ${tr.text('base')} ${tr.text(qty * unit.conversionToBase == 1 ? 'unit' : 'units')}';
  }

  void showPurchaseError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> confirmDiscardIfNeeded(BuildContext confirmContext) async {
    if (items.isEmpty) return true;
    return await showDialog<bool>(
          context: confirmContext,
          builder: (alertContext) => AlertDialog(
            title: Text(tr.text('discard_purchase_title')),
            content: Text(tr.text('discard_purchase_message')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(alertContext, false),
                  child: Text(tr.text('keep_editing'))),
              FilledButton(
                  onPressed: () => Navigator.pop(alertContext, true),
                  child: Text(tr.text('discard'))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> createQuickSupplier(StateSetter setDialogState) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final created = await showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr.text('add_supplier'),
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: tr.text('supplier_name')),
                autofocus: true),
            const SizedBox(height: 12),
            TextField(
                controller: phoneController,
                decoration: InputDecoration(labelText: tr.text('phone'))),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(tr.text('save')),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                    sheetContext,
                    Supplier(
                      id: 'supplier_${DateTime.now().microsecondsSinceEpoch}',
                      name: name,
                      phone: phoneController.text.trim(),
                      address: '',
                      notes: '',
                    ));
              },
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    if (created == null) return;
    try {
      await widget.store.addOrUpdateSupplier(created);
      purchaseSuppliers = <Supplier>[created, ...purchaseSuppliers]
          .fold<Map<String, Supplier>>(<String, Supplier>{}, (map, supplier) {
            map[supplier.id] = supplier;
            return map;
          })
          .values
          .toList(growable: false);
      supplierId = created.id;
      supplierName = created.name;
      setDialogState(() {});
    } catch (error) {
      if (context.mounted) {
        showPurchaseError(
            localizedErrorText(AppLocalizations.of(context), error));
      }
    }
  }

  Future<void> createQuickProduct(StateSetter setDialogState) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final barcodeQuickController = TextEditingController();
    var unit = '';
    String generateBarcode() {
      final used = widget.store.products
          .map((item) => item.barcode.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      var seed = DateTime.now().microsecondsSinceEpoch % 1000000000000;
      String value;
      do {
        final body = seed.toString().padLeft(12, '0');
        var sum = 0;
        for (var index = 0; index < body.length; index++) {
          sum += int.parse(body[index]) * (index.isEven ? 1 : 3);
        }
        value = '$body${(10 - (sum % 10)) % 10}';
        seed = (seed + 1) % 1000000000000;
      } while (used.contains(value));
      return value;
    }

    final created = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr.text('add_product'),
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                      labelText: '${tr.text('product_name')} *'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? tr.text('required') : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: barcodeQuickController,
                  decoration: InputDecoration(
                    labelText: '${tr.text('barcode')} *',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: tr.text('generate_barcode'),
                          onPressed: () =>
                              barcodeQuickController.text = generateBarcode(),
                          icon: const Icon(Icons.qr_code_2_outlined),
                        ),
                        IconButton(
                          tooltip: tr.text('scan_with_camera'),
                          onPressed: () async {
                            final code = await _scanBarcodeWithCamera();
                            if (code == null) return;
                            barcodeQuickController.text = code;
                          },
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                      ],
                    ),
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? tr.text('required') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unit.isEmpty ? null : unit,
                  decoration:
                      InputDecoration(labelText: '${tr.text('unit')} *'),
                  items: widget.store.units
                      .map((item) =>
                          item.code.isNotEmpty ? item.code : item.nameEn)
                      .where((value) => value.trim().isNotEmpty)
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setSheetState(() => unit = value ?? ''),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? tr.text('required') : null,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save')),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final now = DateTime.now().microsecondsSinceEpoch;
                    Navigator.pop(
                        sheetContext,
                        Product(
                          id: 'product_$now',
                          name: nameController.text.trim(),
                          code: 'PRD-$now',
                          barcode: barcodeQuickController.text.trim(),
                          price: 0,
                          cost: 0,
                          stock: 0,
                          category: 'General',
                          unit: unit,
                          trackStock: true,
                          isActive: true,
                        ));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    barcodeQuickController.dispose();
    if (created == null) return;
    try {
      await widget.store.addOrUpdateProduct(created);
      selectedProduct = created;
      selectedUnit = created.effectivePurchaseUnits.first;
      selectedExpiryDate =
          created.expiryTrackingEnabled && created.defaultShelfLifeDays > 0
              ? DateTime.now().add(Duration(days: created.defaultShelfLifeDays))
              : null;
      purchaseProducts = widget.store.products
          .where((product) => product.trackStock && product.isActive)
          .toList();
      applySuggestedSupplierPrice();
      setDialogState(() {});
    } catch (error) {
      if (context.mounted) {
        showPurchaseError(
            localizedErrorText(AppLocalizations.of(context), error));
      }
    }
  }

  Future<void> editPurchaseLine(
    PurchaseItem item,
    StateSetter setDialogState,
    BuildContext purchaseDialogContext,
  ) async {
    final productMatches =
        purchaseProducts.where((p) => p.id == item.productId).toList();
    final product = productMatches.isEmpty ? null : productMatches.first;
    final availableUnits = product?.effectivePurchaseUnits ??
        <ProductSaleUnit>[
          ProductSaleUnit(
            id: item.purchaseUnitId,
            name: item.purchaseUnitName.isEmpty
                ? tr.text('unit')
                : item.purchaseUnitName,
            conversionToBase: item.conversionToBase,
            price: item.unitCost,
            originalPrice: item.originalUnitCost ?? item.unitCost,
            originalCurrency: item.unitCostCurrency,
            isDefault: true,
          ),
        ];
    ProductSaleUnit editUnit = availableUnits.firstWhere(
        (unit) => unit.id == item.purchaseUnitId,
        orElse: () => availableUnits.first);
    String editCurrency = item.unitCostCurrency;
    DateTime? editExpiry = item.batchAllocations.isNotEmpty
        ? item.batchAllocations.first.expirationDate
        : null;
    final editQtyController =
        TextEditingController(text: _formatQuantity(item.quantity));
    final editCostController = TextEditingController(
        text: (item.originalUnitCost ??
                fromUsdReferencePrice(
                    item.unitCost, editCurrency, widget.store.storeProfile))
            .toStringAsFixed(editCurrency == 'LBP' ? 0 : 2));
    final updated = await showModalBottomSheet<PurchaseItem>(
      context: purchaseDialogContext,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      isDismissible: false,
      builder: (editContext) => StatefulBuilder(
        builder: (editContext, setEditState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(editContext).bottom),
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(tr.text('edit_purchase_line'),
                                    style: Theme.of(editContext)
                                        .textTheme
                                        .titleLarge)),
                            IconButton(
                              tooltip: tr.text('cancel'),
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(editContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: editUnit.id,
                          decoration: InputDecoration(
                              labelText: tr.text('purchase_unit')),
                          items: availableUnits
                              .map((unit) => DropdownMenuItem(
                                  value: unit.id,
                                  child: Text(
                                      '${unit.name} × ${_formatQuantity(unit.conversionToBase)}')))
                              .toList(),
                          onChanged: (value) {
                            final matches = availableUnits
                                .where((unit) => unit.id == value)
                                .toList();
                            if (matches.isNotEmpty) {
                              setEditState(() => editUnit = matches.first);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: editQtyController,
                            decoration:
                                InputDecoration(labelText: tr.text('quantity')),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true)),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: editCostController,
                            decoration: InputDecoration(
                                labelText: tr.text('unit_cost')),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: editCurrency,
                          decoration:
                              InputDecoration(labelText: tr.text('currency')),
                          items: const [
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'LBP', child: Text('LBP'))
                          ],
                          onChanged: (value) =>
                              setEditState(() => editCurrency = value ?? 'USD'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.event_outlined),
                          onPressed: product?.expiryTrackingEnabled != true
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: editContext,
                                    initialDate: editExpiry ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 36500)),
                                  );
                                  if (picked != null) {
                                    setEditState(() => editExpiry = picked);
                                  }
                                },
                          label: Text(product?.expiryTrackingEnabled != true
                              ? '${tr.text('expiration_date')} — ${tr.text('disabled')}'
                              : editExpiry == null
                                  ? '${tr.text('expiration_date')} *'
                                  : MaterialLocalizations.of(editContext)
                                      .formatMediumDate(editExpiry!)),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                                child: TextButton(
                                    onPressed: () => Navigator.pop(editContext),
                                    child: Text(tr.text('cancel')))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  final qty = double.tryParse(
                                          editQtyController.text.trim()) ??
                                      0;
                                  final enteredCost = double.tryParse(
                                          editCostController.text.trim()) ??
                                      -1;
                                  if (qty <= 0 ||
                                      enteredCost < 0 ||
                                      editUnit.conversionToBase <= 0) {
                                    return;
                                  }
                                  if (product != null &&
                                      !product.allowsDecimalQuantity &&
                                      qty % 1 != 0) {
                                    return;
                                  }
                                  if (product?.expiryTrackingEnabled == true &&
                                      editExpiry == null) {
                                    return;
                                  }
                                  Navigator.pop(
                                      editContext,
                                      PurchaseItem(
                                        lineId: item.lineId,
                                        productId: item.productId,
                                        productName: item.productName,
                                        quantity: qty,
                                        purchaseUnitId: editUnit.id,
                                        purchaseUnitName: editUnit.name,
                                        conversionToBase:
                                            editUnit.conversionToBase,
                                        unitCost: toUsdReferencePrice(
                                            enteredCost,
                                            editCurrency,
                                            widget.store.storeProfile),
                                        originalUnitCost: enteredCost,
                                        unitCostCurrency: editCurrency,
                                        exchangeRateAtEntry: widget
                                            .store.storeProfile.usdToLbpRate,
                                        batchAllocations: product
                                                    ?.expiryTrackingEnabled ==
                                                true
                                            ? <BatchAllocation>[
                                                BatchAllocation(
                                                  batchId: item.batchAllocations
                                                          .isNotEmpty
                                                      ? item.batchAllocations
                                                          .first.batchId
                                                      : '',
                                                  quantity: qty *
                                                      editUnit.conversionToBase,
                                                  expirationDate: editExpiry,
                                                  supplierBatchNumber: item
                                                          .batchAllocations
                                                          .isNotEmpty
                                                      ? item
                                                          .batchAllocations
                                                          .first
                                                          .supplierBatchNumber
                                                      : '',
                                                  manufacturingDate: item
                                                          .batchAllocations
                                                          .isNotEmpty
                                                      ? item
                                                          .batchAllocations
                                                          .first
                                                          .manufacturingDate
                                                      : null,
                                                )
                                              ]
                                            : const <BatchAllocation>[],
                                      ));
                                },
                                child: Text(tr.text('save')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    editQtyController.dispose();
    editCostController.dispose();
    if (updated != null) {
      final index = items.indexOf(item);
      if (index >= 0) setDialogState(() => items[index] = updated);
    }
  }
}
