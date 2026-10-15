// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: curly_braces_in_flow_control_structures
part of 'manufacturing_page.dart';

extension _ManufacturingPageStatePart2 on _ManufacturingPageState {
  Future<void> _showBomDialog({BillOfMaterials? bom}) async {
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) {
      return;
    }
    final products = widget.store.catalog.stockTrackedProducts;
    if (products.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('create_two_stock_products_first'))));
      return;
    }
    final productById = {for (final product in products) product.id: product};
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    String defaultBomName(Product product) =>
        '${isArabic ? 'وصفة' : 'BOM'} - ${product.name}';

    Product? output = productById[bom?.outputProductId];
    final nameController = TextEditingController(
      text: bom?.name ?? (output != null ? defaultBomName(output) : ''),
    );
    final outputQtyController =
        TextEditingController(text: (bom?.outputQuantity ?? 1).toString());
    final componentProductIds = <String?>[
      for (final item in bom?.components ?? const <BillOfMaterialsLine>[])
        item.productId
    ];
    final componentQtyControllers = <TextEditingController>[
      for (final item in bom?.components ?? const <BillOfMaterialsLine>[])
        TextEditingController(text: item.quantity.toString())
    ];
    if (componentProductIds.isEmpty) {
      componentProductIds.add(null);
      componentQtyControllers.add(TextEditingController());
    }

    List<Product> matchingProducts(String query, {String? excludedId}) {
      final normalized = query.trim().toLowerCase();
      final matches = products.where((product) {
        if (product.id == excludedId) return false;
        if (normalized.isEmpty) return true;
        return product.name.toLowerCase().contains(normalized) ||
            product.code.toLowerCase().contains(normalized) ||
            product.barcode.toLowerCase().contains(normalized);
      }).toList(growable: false);
      matches
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return matches.take(30).toList(growable: false);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget productSearchField({
            required String fieldKey,
            required String label,
            required String? selectedProductId,
            required ValueChanged<Product> onSelected,
            String? excludedId,
          }) {
            final selected = selectedProductId == null
                ? null
                : productById[selectedProductId];
            return RawAutocomplete<Product>(
              key: ValueKey('$fieldKey-${selectedProductId ?? 'empty'}'),
              initialValue: TextEditingValue(text: selected?.name ?? ''),
              displayStringForOption: (product) => product.name,
              optionsBuilder: (value) =>
                  matchingProducts(value.text, excludedId: excludedId),
              onSelected: onSelected,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: _localizedText(
                      ar: 'ابحث عن اسم المنتج',
                      en: 'Search product name',
                      fr: 'Rechercher le produit',
                    ),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onTap: () => controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  ),
                );
              },
              optionsViewBuilder: (context, onSelectedOption, options) {
                final list = options.toList(growable: false);
                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 280, maxWidth: 520),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = list[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(product.name),
                            subtitle: product.code.trim().isEmpty
                                ? null
                                : Text(product.code),
                            onTap: () => onSelectedOption(product),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          }

          return AlertDialog(
            title: Text(bom == null ? _t('new_bom') : _t('edit')),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    productSearchField(
                      fieldKey: 'bom-output',
                      label: _localizedText(
                          ar: 'منتج الوصفة',
                          en: 'Recipe product',
                          fr: 'Produit de la recette'),
                      selectedProductId: output?.id,
                      onSelected: (selected) {
                        setDialogState(() {
                          output = selected;
                          for (var i = 0;
                              i < componentProductIds.length;
                              i += 1) {
                            if (componentProductIds[i] == selected.id) {
                              componentProductIds[i] = null;
                            }
                          }
                          if (bom == null) {
                            nameController.text = defaultBomName(selected);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: _t('bom_name')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: outputQtyController,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: _t('output_quantity')),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _t('components'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(componentProductIds.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: productSearchField(
                                fieldKey: 'bom-component-$index',
                                label: _localizedText(
                                  ar: 'المكوّن',
                                  en: 'Component',
                                  fr: 'Composant',
                                ),
                                selectedProductId: componentProductIds[index],
                                excludedId: output?.id,
                                onSelected: (selected) => setDialogState(() {
                                  componentProductIds[index] = selected.id;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: componentQtyControllers[index],
                                keyboardType: TextInputType.number,
                                decoration:
                                    InputDecoration(labelText: _t('qty')),
                              ),
                            ),
                            IconButton(
                              onPressed: componentProductIds.length == 1
                                  ? null
                                  : () => setDialogState(() {
                                        componentProductIds.removeAt(index);
                                        componentQtyControllers.removeAt(index);
                                      }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setDialogState(() {
                        componentProductIds.add(null);
                        componentQtyControllers.add(TextEditingController());
                      }),
                      icon: const Icon(Icons.add),
                      label: Text(_t('add_component')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_t('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(_t('save'))),
            ],
          );
        },
      ),
    );
    if (confirmed != true) {
      for (final controller in componentQtyControllers) {
        controller.dispose();
      }
      nameController.dispose();
      outputQtyController.dispose();
      return;
    }
    try {
      final selectedOutput = output;
      if (selectedOutput == null) {
        throw StateError(_localizedText(
          ar: 'يرجى اختيار منتج الوصفة.',
          en: 'Select the recipe product.',
          fr: 'Sélectionnez le produit de la recette.',
        ));
      }
      final components = <BillOfMaterialsLine>[];
      for (var i = 0; i < componentProductIds.length; i++) {
        final componentId = componentProductIds[i];
        final product = componentId == null ? null : productById[componentId];
        final quantity = double.tryParse(componentQtyControllers[i].text) ?? 0;
        if (product == null || quantity <= 0) {
          throw StateError(_localizedText(
            ar: 'يرجى اختيار المنتج وإدخال كمية صحيحة لكل مكوّن.',
            en: 'Select a product and enter a valid quantity for each component.',
            fr: 'Sélectionnez un produit et une quantité valide pour chaque composant.',
          ));
        }
        components.add(BillOfMaterialsLine(
          productId: product.id,
          productName: product.name,
          quantity: quantity,
          unitCost: product.usdCost,
        ));
      }
      if (bom == null) {
        await widget.store.inventory.createBillOfMaterials(
          name: nameController.text,
          outputProductId: selectedOutput.id,
          outputQuantity: double.tryParse(outputQtyController.text) ?? 1,
          components: components,
        );
      } else {
        await widget.store.inventory.updateBillOfMaterials(
          id: bom.id,
          name: nameController.text,
          outputProductId: selectedOutput.id,
          outputQuantity: double.tryParse(outputQtyController.text) ?? 1,
          components: components,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    } finally {
      for (final controller in componentQtyControllers) {
        controller.dispose();
      }
      nameController.dispose();
      outputQtyController.dispose();
    }
  }

  Future<void> _confirmDeleteBom(BillOfMaterials bom) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('delete')),
        content: Text('${_t('bom_name')}: ${bom.name}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.inventory.deleteBillOfMaterials(bom.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<void> _showCompleteOrderDialog(BillOfMaterials bom) async {
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) return;
    final qtyController =
        TextEditingController(text: bom.outputQuantity.toString());
    final warehouses = widget.store.inventory.warehouses;
    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('warehouse_not_found'))),
      );
      return;
    }
    var rawWarehouseId =
        widget.store.inventory.resolveWarehouseForPurchase().id;
    var finishedWarehouseId =
        widget.store.inventory.resolveWarehouseForSale().id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final rawWarehouse = warehouses.firstWhere(
            (item) => item.id == rawWarehouseId,
            orElse: () => warehouses.first,
          );
          final finishedWarehouse = warehouses.firstWhere(
            (item) => item.id == finishedWarehouseId,
            orElse: () => warehouses.first,
          );
          final componentAvailability = bom.components.map((component) {
            final available = widget.store.inventory
                .stockForWarehouse(component.productId, rawWarehouse.id);
            return '${component.productName}: ${available.toStringAsFixed(2)}';
          }).toList(growable: false);
          return AlertDialog(
            title: Text(
                _tf('produce_product', {'product': bom.outputProductName})),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _t('quantity_to_produce'),
                        )),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: rawWarehouse.id,
                      decoration: InputDecoration(
                        labelText: _t('raw_materials_warehouse'),
                      ),
                      items: warehouses
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => rawWarehouseId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: finishedWarehouse.id,
                      decoration: InputDecoration(
                        labelText: _t('finished_goods_warehouse'),
                      ),
                      items: warehouses
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => finishedWarehouseId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _t('available_in_raw_warehouse'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...componentAvailability.map(Text.new),
                    const SizedBox(height: 12),
                    FutureBuilder<double>(
                      future: widget.store.inventory
                          .estimateBillOfMaterialsUnitCost(
                        bom,
                        warehouseId: rawWarehouse.id,
                      ),
                      initialData: bom.unitCost,
                      builder: (context, snapshot) {
                        final cost = snapshot.data ?? bom.unitCost;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _localizedText(
                              ar: 'تكلفة الوحدة التقديرية من الدُفعات: ${cost.toStringAsFixed(2)} USD',
                              en: 'Estimated unit cost from batches: ${cost.toStringAsFixed(2)} USD',
                              fr: 'Coût unitaire estimé des lots : ${cost.toStringAsFixed(2)} USD',
                            ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_t('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(_localizedText(
                    ar: 'بدء التصنيع',
                    en: 'Start production',
                    fr: 'Démarrer la fabrication',
                  ))),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      final quantity = double.tryParse(qtyController.text) ?? 0;
      await widget.store.inventory.startManufacturingOrder(
        bomId: bom.id,
        quantity: quantity,
        rawMaterialsWarehouseId: rawWarehouseId,
        rawMaterialsWarehouseName: warehouses
            .firstWhere((item) => item.id == rawWarehouseId,
                orElse: () => warehouses.first)
            .name,
        finishedGoodsWarehouseId: finishedWarehouseId,
        finishedGoodsWarehouseName: warehouses
            .firstWhere((item) => item.id == finishedWarehouseId,
                orElse: () => warehouses.first)
            .name,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<void> _confirmDeleteManufacturingOrder(
    ManufacturingOrder order,
  ) async {
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) {
      return;
    }
    if (<String>{'completed', 'complete'}
        .contains(order.status.trim().toLowerCase())) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          ar: 'حذف أمر التصنيع',
          en: 'Delete manufacturing order',
          fr: 'Supprimer l’ordre de fabrication',
        )),
        content: Text(_localizedText(
          ar: 'هل تريد حذف الأمر ${order.orderNo}؟\n\n'
              'يمكن حذف الأمر لأنه ما زال قيد التصنيع ولم يتم ترحيل حركات المخزون الخاصة بإتمامه.',
          en: 'Delete order ${order.orderNo}?\n\n'
              'This order can be deleted because it is still in production and no completion inventory movements have been posted.',
          fr: 'Supprimer l’ordre ${order.orderNo} ?\n\n'
              'Cet ordre peut être supprimé car il est toujours en fabrication et aucun mouvement de stock de fin n’a été validé.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(_localizedText(
              ar: 'تأكيد الحذف',
              en: 'Confirm delete',
              fr: 'Confirmer la suppression',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.store.inventory.deleteManufacturingOrder(order.id);
      if (!mounted) return;
      setState(() {
        _selectedOrderIds.remove(order.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizedText(
            ar: 'تم حذف أمر التصنيع.',
            en: 'Manufacturing order deleted.',
            fr: 'Ordre de fabrication supprimé.',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedErrorText(AppLocalizations.of(context), error),
          ),
        ),
      );
    }
  }

  Future<void> _showOrderDetails(ManufacturingOrder order) async {
    BillOfMaterials? bom;
    for (final candidate in widget.store.inventory.billsOfMaterials) {
      if (candidate.id == order.bomId) {
        bom = candidate;
        break;
      }
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          ar: 'تفاصيل أمر التصنيع',
          en: 'Manufacturing order details',
          fr: 'Détails de l’ordre de fabrication',
        )),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _orderDetailRow('رقم الأمر', 'Order number', order.orderNo),
                _orderDetailRow('الوصفة', 'Recipe', order.bomName),
                _orderDetailRow(
                    'المنتج الناتج', 'Output product', order.outputProductName),
                _orderDetailRow(
                    'الكمية', 'Quantity', order.quantity.toString()),
                _orderDetailRow('الحالة', 'Status',
                    _manufacturingStatusLabel(order.status)),
                _orderDetailRow('مستودع المواد الأولية',
                    'Raw materials warehouse', order.rawMaterialsWarehouseName),
                _orderDetailRow(
                    'مستودع المنتجات التامة',
                    'Finished goods warehouse',
                    order.finishedGoodsWarehouseName),
                _orderDetailRow(
                    'التاريخ', 'Date', _formatOrderDate(order.date)),
                if (order.status.toLowerCase() != 'in_progress') ...[
                  const Divider(height: 24),
                  _orderDetailRow(
                      'التكلفة الفعلية للمواد',
                      'Actual material cost',
                      order.totalMaterialCost.toStringAsFixed(2)),
                  _orderDetailRow('قيمة الهدر', 'Waste value',
                      order.totalWasteCost.toStringAsFixed(2)),
                  _orderDetailRow(
                      'تكلفة الإنتاج المقبول',
                      'Accepted output cost',
                      order.totalEligibleCost.toStringAsFixed(2)),
                  _orderDetailRow('تكلفة الوحدة الفعلية', 'Actual unit cost',
                      order.actualUnitCost.toStringAsFixed(4)),
                  _orderDetailRow(
                      'مرجع القيد', 'Journal reference', order.journalEntryId),
                  if (order.reversalJournalEntryId.isNotEmpty)
                    _orderDetailRow('قيد العكس', 'Reversal journal',
                        order.reversalJournalEntryId),
                  if (order.reversalReason.isNotEmpty)
                    _orderDetailRow(
                        'سبب العكس', 'Reversal reason', order.reversalReason),
                ],
                if (order.notes.trim().isNotEmpty)
                  _orderDetailRow('ملاحظات', 'Notes', order.notes),
                if (bom != null) ...[
                  const Divider(height: 24),
                  Text(
                    _localizedText(
                      ar: 'مكوّنات الوصفة',
                      en: 'Recipe components',
                      fr: 'Composants de la recette',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ...bom.components.map(
                    (component) => _orderDetailRow(
                      component.productName,
                      component.productName,
                      '${(component.quantity * order.quantity / bom!.outputQuantity).toStringAsFixed(2)} (${_localizedText(ar: 'للوصفة', en: 'per recipe', fr: 'par recette')}: ${component.quantity})',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }
}
