part of 'purchases_page.dart';

extension _PurchaseDialogSessionActions2 on _PurchaseDialogSession {
  Future<void> updateSupplierPricesFromItemsIfNeeded(
      BuildContext promptContext, List<PurchaseItem> purchaseItems) async {
    if (supplierId.trim().isEmpty || purchaseItems.isEmpty) return;
    final latestByProduct = <String, PurchaseItem>{};
    for (final item in purchaseItems) {
      latestByProduct[item.productId] = item;
    }
    final updates = <SupplierProductPrice>[];
    for (final item in latestByProduct.values) {
      final productId = item.productId.trim();
      if (productId.isEmpty) continue;
      final existing = widget.store.supplierProductPriceFor(
          productId: productId, supplierId: supplierId);
      final newCurrency =
          item.unitCostCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
      final newBaseCost = newCurrency == 'LBP' && item.originalUnitCost != null
          ? item.originalUnitCost! /
              (item.conversionToBase <= 0 ? 1 : item.conversionToBase)
          : item.unitCostPerBase;
      final hasChanged = existing == null ||
          (existing.cost - newBaseCost).abs() > 0.0001 ||
          existing.currency.toUpperCase() != newCurrency;
      if (!hasChanged) continue;
      updates.add(SupplierProductPrice(
        id: existing?.id ?? '',
        productId: productId,
        supplierId: supplierId,
        cost: newBaseCost,
        currency: newCurrency,
        isPreferred: existing?.isPreferred ??
            widget.store.supplierProductPricesForProduct(productId).isEmpty,
        supplierSku: existing?.supplierSku ?? '',
        minOrderQty: existing?.minOrderQty,
        leadTimeDays: existing?.leadTimeDays,
        notes: existing?.notes ?? '',
        priceHistory: existing?.priceHistory ?? const [],
        createdAt: existing?.createdAt,
        updatedAt: DateTime.now(),
        deviceId: existing?.deviceId ?? '',
        syncStatus: existing?.syncStatus ?? 'pending',
        storeId: existing?.storeId ?? '',
        branchId: existing?.branchId ?? '',
        version: existing?.version ?? 1,
        lastModifiedByDeviceId: existing?.lastModifiedByDeviceId ?? '',
      ));
    }
    if (updates.isEmpty) return;
    final shouldUpdate = await showDialog<bool>(
      context: promptContext,
      builder: (context) => AlertDialog(
        title: Text(tr.text('update_supplier_prices')),
        content: Text(tr.text('update_supplier_prices_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('no'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('yes'))),
        ],
      ),
    );
    if (shouldUpdate != true) return;
    for (final price in updates) {
      await widget.store.addOrUpdateSupplierProductPrice(price);
    }
  }

  bool addPurchaseLine(Product product, ProductSaleUnit unit, double qty,
      double enteredCost, String currency, StateSetter setDialogState) {
    if (qty <= 0) {
      showPurchaseError(tr.text('invalid_purchase_quantity'));
      return false;
    }
    if (enteredCost < 0) {
      showPurchaseError(tr.text('unit_cost_required'));
      return false;
    }
    if (unit.conversionToBase <= 0) {
      showPurchaseError(tr.text('invalid_purchase_unit_conversion'));
      return false;
    }
    if (!product.allowsDecimalQuantity && qty % 1 != 0) {
      showPurchaseError(tr.text('countable_whole_quantity_required'));
      return false;
    }
    if (product.expiryTrackingEnabled && selectedExpiryDate == null) {
      showPurchaseError(tr.text('expiration_date'));
      return false;
    }
    final cost =
        toUsdReferencePrice(enteredCost, currency, widget.store.storeProfile);
    items.add(PurchaseItem(
      lineId:
          'purchase_line_${DateTime.now().microsecondsSinceEpoch}_${items.length}',
      productId: product.id,
      productName: product.name,
      quantity: qty,
      purchaseUnitId: unit.id,
      purchaseUnitName: unit.name,
      conversionToBase: unit.conversionToBase,
      unitCost: cost,
      originalUnitCost: enteredCost,
      unitCostCurrency: currency,
      exchangeRateAtEntry: widget.store.storeProfile.usdToLbpRate,
      batchAllocations: product.expiryTrackingEnabled
          ? <BatchAllocation>[
              BatchAllocation(
                batchId: '',
                quantity: qty * unit.conversionToBase,
                expirationDate: selectedExpiryDate,
              ),
            ]
          : const <BatchAllocation>[],
    ));
    setDialogState(() {});
    return true;
  }

  void resetProductEntryAfterAdd(StateSetter setDialogState) {
    selectedProduct = null;
    selectedUnit = null;
    selectedExpiryDate = null;
    productSearchController.clear();
    qtyController.text = '1';
    costController.clear();
    setDialogState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialogShortcutFocusNode.canRequestFocus) {
        productSearchFocusNode.requestFocus();
      }
    });
  }

  void addSelectedPurchaseLine(StateSetter setDialogState) {
    final product = selectedProduct;
    final unit = selectedUnit;
    if (product == null || unit == null) return;
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    final enteredCost = double.tryParse(costController.text.trim()) ?? -1;
    final added = addPurchaseLine(
      product,
      unit,
      qty,
      enteredCost,
      costCurrency,
      setDialogState,
    );
    if (added) resetProductEntryAfterAdd(setDialogState);
  }

  ({Product product, ProductSaleUnit unit})? findPurchaseProductByBarcode(
      String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) return null;
    for (final product in purchaseProducts) {
      final unitMatch = product.purchaseUnitForBarcode(code);
      if (unitMatch != null) return (product: product, unit: unitMatch);
      if (product.code.trim() == code || product.barcode.trim() == code) {
        return (product: product, unit: product.effectivePurchaseUnits.first);
      }
    }
    return null;
  }

  Future<void> choosePurchaseProduct(StateSetter setDialogState,
      {bool scanFirst = false}) async {
    if (scanFirst) {
      final code = await _scanBarcodeWithCamera();
      if (code == null) return;
      final match = findPurchaseProductByBarcode(code);
      if (match == null) {
        BarcodeFeedbackService.playError(force: true);
        showPurchaseError(tr.text('barcode_not_registered_purchase'));
        return;
      }
      selectedProduct = match.product;
      selectedUnit = match.unit;
      selectedExpiryDate = match.product.expiryTrackingEnabled &&
              match.product.defaultShelfLifeDays > 0
          ? DateTime.now()
              .add(Duration(days: match.product.defaultShelfLifeDays))
          : null;
      productSearchController.text = match.product.name;
      applySuggestedSupplierPrice();
      BarcodeFeedbackService.play(force: true);
      setDialogState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        qtyFocusNode.requestFocus();
      });
      return;
    }

    final pickerController =
        TextEditingController(text: productSearchController.text.trim());
    var pickerQuery = pickerController.text.trim();
    final picked =
        await showModalBottomSheet<({Product product, ProductSaleUnit unit})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (pickerContext) => StatefulBuilder(
        builder: (pickerContext, setPickerState) {
          final matchesFuture =
              _resolvePurchaseSearchProducts(purchaseProducts, pickerQuery);
          final height = MediaQuery.sizeOf(pickerContext).height * 0.82;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(pickerContext).bottom),
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(tr.text('search_product'),
                                    style: Theme.of(pickerContext)
                                        .textTheme
                                        .titleLarge)),
                            IconButton(
                              tooltip: tr.text('cancel'),
                              onPressed: () => Navigator.pop(pickerContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: TextField(
                          controller: pickerController,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: tr.text('search_product'),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: tr.text('scan_with_camera'),
                              icon: const Icon(Icons.camera_alt_outlined),
                              onPressed: () async {
                                final code = await _scanBarcodeWithCamera();
                                if (code == null) return;
                                final match =
                                    findPurchaseProductByBarcode(code);
                                if (match == null) {
                                  BarcodeFeedbackService.playError(force: true);
                                  showPurchaseError(tr
                                      .text('barcode_not_registered_purchase'));
                                  return;
                                }
                                if (pickerContext.mounted) {
                                  Navigator.pop(pickerContext, match);
                                }
                              },
                            ),
                          ),
                          onChanged: (value) =>
                              setPickerState(() => pickerQuery = value),
                        ),
                      ),
                      Expanded(
                        child: FutureBuilder<List<Product>>(
                          future: matchesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator.adaptive(),
                              );
                            }
                            final matches = snapshot.data ?? const <Product>[];
                            if (matches.isEmpty) {
                              return Center(
                                  child: Text(tr.text('no_products')));
                            }
                            return ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: matches.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = matches[index];
                                final unit =
                                    product.effectivePurchaseUnits.first;
                                final configuredPrice = supplierId.isEmpty
                                    ? null
                                    : widget.store.supplierProductPriceFor(
                                        productId: product.id,
                                        supplierId: supplierId);
                                final subtitleParts = <String>[
                                  if (product.code.trim().isNotEmpty)
                                    product.code.trim(),
                                  if (product.barcode.trim().isNotEmpty)
                                    product.barcode.trim(),
                                  '${tr.text('stock')}: ${_formatQuantity(widget.store.stockForWarehouse(product.id, selectedWarehouseId))}',
                                  if (configuredPrice != null)
                                    '${tr.text('supplier_price')}: ${formatCurrency(configuredPrice.cost, currency: configuredPrice.currency)}',
                                ];
                                return ListTile(
                                  leading:
                                      const Icon(Icons.inventory_2_outlined),
                                  title: Text(product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(subtitleParts.join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.pop(pickerContext,
                                      (product: product, unit: unit)),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add_box_outlined),
                          label: Text(tr.text('add_product')),
                          onPressed: () async {
                            Navigator.pop(pickerContext);
                            await createQuickProduct(setDialogState);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    pickerController.dispose();
    if (picked == null) return;
    selectedProduct = picked.product;
    selectedUnit = picked.unit;
    selectedExpiryDate = picked.product.expiryTrackingEnabled &&
            picked.product.defaultShelfLifeDays > 0
        ? DateTime.now()
            .add(Duration(days: picked.product.defaultShelfLifeDays))
        : null;
    productSearchController.text = picked.product.name;
    applySuggestedSupplierPrice();
    setDialogState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyFocusNode.requestFocus();
    });
  }

  Future<List<PurchaseItem>?> collectRequiredBatchAllocations(
    BuildContext dialogContext,
    List<PurchaseItem> sourceItems,
  ) async {
    final resolvedItems = <PurchaseItem>[];
    for (final item in sourceItems) {
      final productMatches =
          purchaseProducts.where((product) => product.id == item.productId);
      final product = productMatches.isEmpty ? null : productMatches.first;
      if (product == null) {
        resolvedItems.add(item);
        continue;
      }
      if (!product.expiryTrackingEnabled) {
        resolvedItems.add(PurchaseItem(
          lineId: item.lineId,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          unitCost: item.unitCost,
          purchaseUnitId: item.purchaseUnitId,
          purchaseUnitName: item.purchaseUnitName,
          conversionToBase: item.conversionToBase,
          originalUnitCost: item.originalUnitCost,
          unitCostCurrency: item.unitCostCurrency,
          exchangeRateAtEntry: item.exchangeRateAtEntry,
          batchAllocations: const <BatchAllocation>[],
        ));
        continue;
      }
      final existing = item.batchAllocations.length == 1 &&
              (item.batchAllocations.first.quantity - item.baseQuantity)
                      .abs() <=
                  0.000001 &&
              item.batchAllocations.first.expirationDate != null
          ? item.batchAllocations.first
          : null;
      final allocations = existing != null
          ? <BatchAllocation>[existing]
          : await _promptBatchAllocations(
              dialogContext,
              product: product,
              quantity: item.baseQuantity,
            );
      if (allocations == null || allocations.length != 1) return null;
      resolvedItems.add(PurchaseItem(
        lineId: item.lineId,
        productId: item.productId,
        productName: item.productName,
        quantity: item.quantity,
        unitCost: item.unitCost,
        purchaseUnitId: item.purchaseUnitId,
        purchaseUnitName: item.purchaseUnitName,
        conversionToBase: item.conversionToBase,
        originalUnitCost: item.originalUnitCost,
        unitCostCurrency: item.unitCostCurrency,
        exchangeRateAtEntry: item.exchangeRateAtEntry,
        batchAllocations: allocations,
      ));
    }
    return resolvedItems;
  }

  Future<void> savePurchaseFromDialog(BuildContext dialogContext) async {
    if (items.isEmpty) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    try {
      var purchaseItems = List<PurchaseItem>.of(items);
      if (receiveNow) {
        final withBatches =
            await collectRequiredBatchAllocations(dialogContext, purchaseItems);
        if (withBatches == null) return;
        purchaseItems = withBatches;
        if (!dialogContext.mounted) return;
      }
      final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
      final paidAmount = paymentStatus == 'partial'
          ? (double.tryParse(paidAmountController.text.trim()) ?? 0)
          : null;
      if (!editingPostedPurchase &&
          paymentStatus == 'partial' &&
          (paidAmount == null || paidAmount <= 0 || paidAmount > total)) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(content: Text(tr.text('invalid_paid_amount'))));
        return;
      }
      if (editPurchase != null) {
        if (editingReturnedPurchase) {
          await widget.store.editPurchaseReturn(
            purchaseId: editPurchase.id,
            expectedVersion: editPurchase.version,
            supplierId: supplierId,
            supplierName: supplierName,
            items: purchaseItems,
            warehouseId: selectedWarehouseId,
            warehouseName: selectedWarehouseName,
          );
        } else {
          await widget.store.updatePurchaseDraft(
            purchaseId: editPurchase.id,
            expectedVersion: editPurchase.version,
            supplierId: supplierId,
            supplierName: supplierName,
            items: purchaseItems,
            paymentStatus: paymentStatus,
            paymentMethod: paymentMethod,
            paidAmount: paidAmount,
            warehouseId: selectedWarehouseId,
            warehouseName: selectedWarehouseName,
          );
        }
      } else {
        await widget.store.createPurchase(
            supplierId: supplierId,
            supplierName: supplierName,
            items: purchaseItems,
            receiveNow: receiveNow,
            paymentStatus: paymentStatus,
            paymentMethod: paymentMethod,
            paidAmount: paidAmount,
            warehouseId: selectedWarehouseId,
            warehouseName: selectedWarehouseName);
      }
      if (dialogContext.mounted) {
        await updateSupplierPricesFromItemsIfNeeded(
            dialogContext, purchaseItems);
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(editPurchase != null
                ? tr.text('purchase_updated')
                : template == null
                    ? tr.text('purchase_saved')
                    : tr.text('duplicate_purchase_saved_as_draft'))),
      );
      setState(() {});
    } catch (error) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }

  Future<void> cancelPurchaseDialog(BuildContext dialogContext) async {
    if (isClosingPurchaseDialog) return;
    isClosingPurchaseDialog = true;
    try {
      if (await confirmDiscardIfNeeded(dialogContext) &&
          dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } finally {
      isClosingPurchaseDialog = false;
    }
  }

  KeyEventResult handlePurchaseDialogShortcutKey(
      KeyEvent event, BuildContext dialogContext, StateSetter setDialogState) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return KeyEventResult.ignored;
    final action =
        SaleShortcutSettings.load().purchaseDialogActionForKey(keyName);
    if (action == null) return KeyEventResult.ignored;
    switch (action) {
      case PurchaseDialogShortcutAction.chooseProduct:
        choosePurchaseProduct(setDialogState);
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.addLine:
        addSelectedPurchaseLine(setDialogState);
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.savePurchase:
        savePurchaseFromDialog(dialogContext);
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.cancelPurchase:
        cancelPurchaseDialog(dialogContext);
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.toggleReceiveNow:
        setDialogState(() => receiveNow = !receiveNow);
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.focusQuantity:
        qtyFocusNode.requestFocus();
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.focusCost:
        costFocusNode.requestFocus();
        return KeyEventResult.handled;
      case PurchaseDialogShortcutAction.focusPaidAmount:
        paidAmountFocusNode.requestFocus();
        return KeyEventResult.handled;
    }
  }

  bool handlePurchaseDialogHardwareShortcut(KeyEvent event) {
    final dialogContext = activePurchaseDialogContext;
    final setDialogState = activePurchaseDialogSetState;
    if (dialogContext == null ||
        setDialogState == null ||
        ModalRoute.of(dialogContext)?.isCurrent != true) {
      return false;
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      if (qtyFocusNode.hasFocus) {
        costFocusNode.requestFocus();
        return true;
      }
      if (costFocusNode.hasFocus) {
        addLineFocusNode.requestFocus();
        return true;
      }
      if (addLineFocusNode.hasFocus) {
        addSelectedPurchaseLine(setDialogState);
        return true;
      }
      if (productSearchFocusNode.hasFocus) {
        choosePurchaseProduct(setDialogState);
        return true;
      }
    }
    return handlePurchaseDialogShortcutKey(
            event, dialogContext, setDialogState) ==
        KeyEventResult.handled;
  }
}
