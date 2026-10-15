// ignore_for_file: curly_braces_in_flow_control_structures
part of 'manufacturing_page.dart';

extension _ManufacturingPageStatePart3 on _ManufacturingPageState {

  Future<void> _reverseManufacturingOrder(ManufacturingOrder order) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          ar: 'عكس أمر التصنيع',
          en: 'Reverse manufacturing order',
          fr: 'Contrepasser l’ordre de fabrication',
        )),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _localizedText(
              ar: 'سبب العكس (إلزامي)',
              en: 'Reversal reason (required)',
              fr: 'Motif (obligatoire)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_localizedText(
              ar: 'تأكيد العكس',
              en: 'Confirm reversal',
              fr: 'Confirmer',
            )),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (reason.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_localizedText(
          ar: 'سبب العكس إلزامي',
          en: 'A reversal reason is required',
          fr: 'Le motif est obligatoire',
        )),
      ));
      return;
    }
    try {
      await widget.store.reverseManufacturingOrder(
        orderId: order.id,
        reason: reason,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _orderDetailRow(String ar, String en, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              _localizedText(ar: ar, en: en),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatOrderDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showEditOrderDialog(ManufacturingOrder order) async {
    if (<String>{'completed', 'complete', 'reversed', 'posted'}
        .contains(order.status.toLowerCase())) {
      return;
    }
    if (!widget.store.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) return;
    final boms = widget.store.billsOfMaterials
        .where((item) => !item.isDeleted && item.isActive)
        .toList(growable: false);
    final warehouses = widget.store.warehouses;
    if (boms.isEmpty || warehouses.isEmpty) return;
    var bomId = boms.any((item) => item.id == order.bomId)
        ? order.bomId
        : boms.first.id;
    var rawWarehouseId =
        warehouses.any((item) => item.id == order.rawMaterialsWarehouseId)
            ? order.rawMaterialsWarehouseId
            : warehouses.first.id;
    var finishedWarehouseId =
        warehouses.any((item) => item.id == order.finishedGoodsWarehouseId)
            ? order.finishedGoodsWarehouseId
            : warehouses.first.id;
    final qtyController =
        TextEditingController(text: order.quantity.toString());
    final notesController = TextEditingController(text: order.notes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_localizedText(
              ar: 'تعديل أمر التصنيع',
              en: 'Edit manufacturing order',
              fr: 'Modifier l’ordre de fabrication')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: bomId,
                  decoration: InputDecoration(
                      labelText: _localizedText(
                          ar: 'الوصفة', en: 'Recipe', fr: 'Recette')),
                  items: boms
                      .map((item) => DropdownMenuItem(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => bomId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: qtyController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: _t('quantity_to_produce'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: rawWarehouseId,
                  decoration:
                      InputDecoration(labelText: _t('raw_materials_warehouse')),
                  items: warehouses
                      .map((item) => DropdownMenuItem(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null)
                      setDialogState(() => rawWarehouseId = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: finishedWarehouseId,
                  decoration: InputDecoration(
                      labelText: _t('finished_goods_warehouse')),
                  items: warehouses
                      .map((item) => DropdownMenuItem(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null)
                      setDialogState(() => finishedWarehouseId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                        labelText: _localizedText(
                            ar: 'ملاحظات', en: 'Notes', fr: 'Notes'))),
              ]),
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
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      qtyController.dispose();
      notesController.dispose();
      return;
    }
    try {
      final rawWarehouse =
          warehouses.firstWhere((item) => item.id == rawWarehouseId);
      final finishedWarehouse =
          warehouses.firstWhere((item) => item.id == finishedWarehouseId);
      await widget.store.updateManufacturingOrder(
        id: order.id,
        bomId: bomId,
        quantity: double.tryParse(qtyController.text.trim()) ?? 0,
        rawMaterialsWarehouseId: rawWarehouse.id,
        rawMaterialsWarehouseName: rawWarehouse.name,
        finishedGoodsWarehouseId: finishedWarehouse.id,
        finishedGoodsWarehouseName: finishedWarehouse.name,
        notes: notesController.text,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
    } finally {
      qtyController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showFinishOrderDialog(
    ManufacturingOrder order, {
    bool editCompleted = false,
  }) async {
    if (!widget.store.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) return;

    final initialOutputQuantity =
        editCompleted && order.actualOutputQuantity > 0
            ? order.actualOutputQuantity
            : order.quantity;
    final qtyController =
        TextEditingController(text: initialOutputQuantity.toString());
    final bom = widget.store.billsOfMaterials.firstWhere(
      (item) => item.id == order.bomId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing recipe was not found.'),
    );
    final factor = bom.outputQuantity <= 0
        ? 0.0
        : initialOutputQuantity / bom.outputQuantity;
    final historicalConsumed = <String, double>{
      for (final line in order.materialCosts) line.productId: line.quantity,
    };
    final historicalWaste = <String, ManufacturingWasteLine>{
      for (final line in order.wasteLines) line.productId: line,
    };
    final consumedControllers = <String, TextEditingController>{
      for (final component in bom.components)
        component.productId: TextEditingController(
          text: (editCompleted ? historicalConsumed[component.productId] : null)
                  ?.toString() ??
              (component.quantity * factor).toString(),
        ),
    };
    final wasteControllers = <String, TextEditingController>{
      for (final component in bom.components)
        component.productId: TextEditingController(
          text: (editCompleted
                      ? historicalWaste[component.productId]?.quantity
                      : null)
                  ?.toString() ??
              '0',
        ),
    };
    final wasteReasonControllers = <String, TextEditingController>{
      for (final component in bom.components)
        component.productId: TextEditingController(
          text: editCompleted
              ? historicalWaste[component.productId]?.reason ?? ''
              : '',
        ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          ar: editCompleted ? 'تعديل التصنيع المكتمل' : 'تأكيد انتهاء التصنيع',
          en: editCompleted
              ? 'Edit completed manufacturing'
              : 'Confirm production completion',
          fr: editCompleted
              ? 'Modifier la fabrication terminée'
              : 'Confirmer la fin de fabrication',
        )),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.outputProductName),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _localizedText(
                      ar: 'الكمية المصنعة فعلياً',
                      en: 'Actual produced quantity',
                      fr: 'Quantité réellement produite',
                    ),
                    helperText: _localizedText(
                      ar: 'القيمة الافتراضية هي كمية أمر التصنيع',
                      en: 'Defaults to the manufacturing order quantity',
                      fr: 'La valeur par défaut est celle de l’ordre de fabrication',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _localizedText(
                    ar: 'الاستهلاك والهدر الفعلي',
                    en: 'Actual consumption and waste',
                    fr: 'Consommation et perte réelles',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final component in bom.components)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(component.productName),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller:
                                  consumedControllers[component.productId],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: _localizedText(
                                  ar: 'المستهلك فعلياً',
                                  en: 'Actually consumed',
                                  fr: 'Consommé réellement',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: wasteControllers[component.productId],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: _localizedText(
                                  ar: 'كمية الهدر',
                                  en: 'Waste quantity',
                                  fr: 'Quantité perdue',
                                ),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        TextField(
                          controller:
                              wasteReasonControllers[component.productId],
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              ar: 'سبب الهدر (عند وجوده)',
                              en: 'Waste reason (when applicable)',
                              fr: 'Motif de perte (le cas échéant)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(editCompleted ? Icons.save_outlined : Icons.task_alt),
            label: Text(_localizedText(
              ar: editCompleted ? 'حفظ التعديل' : 'تأكيد الانتهاء',
              en: editCompleted ? 'Save edit' : 'Confirm completion',
              fr: editCompleted ? 'Enregistrer' : 'Confirmer la fin',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      qtyController.dispose();
      for (final controller in consumedControllers.values) {
        controller.dispose();
      }
      for (final controller in wasteControllers.values) {
        controller.dispose();
      }
      for (final controller in wasteReasonControllers.values) {
        controller.dispose();
      }
      return;
    }

    try {
      final actualQuantity = double.tryParse(qtyController.text.trim()) ?? 0;
      if (actualQuantity <= 0) {
        throw ArgumentError(
          _localizedText(
            ar: 'يجب أن تكون الكمية المصنعة أكبر من صفر.',
            en: 'Produced quantity must be greater than zero.',
            fr: 'La quantité produite doit être supérieure à zéro.',
          ),
        );
      }
      final output = widget.store.products.firstWhere(
        (item) => item.id == order.outputProductId,
      );
      final outputBatches = output.expiryTrackingEnabled
          ? await showBatchAllocationDialog(
              context,
              product: output,
              expectedQuantity: actualQuantity,
              sourceId: order.id,
            )
          : null;
      if (output.expiryTrackingEnabled && outputBatches == null) return;

      final consumed = <String, double>{
        for (final component in bom.components)
          component.productId: double.tryParse(
                  consumedControllers[component.productId]!.text.trim()) ??
              0,
      };
      final waste = <String, double>{
        for (final component in bom.components)
          component.productId: double.tryParse(
                  wasteControllers[component.productId]!.text.trim()) ??
              0,
      };
      final wasteReasons = <String, String>{
        for (final component in bom.components)
          component.productId:
              wasteReasonControllers[component.productId]!.text.trim(),
      };
      if (editCompleted) {
        await widget.store.editCompletedManufacturingOrder(
          orderId: order.id,
          expectedVersion: order.version,
          bomId: order.bomId,
          quantity: actualQuantity,
          rawMaterialsWarehouseId: order.rawMaterialsWarehouseId,
          rawMaterialsWarehouseName: order.rawMaterialsWarehouseName,
          finishedGoodsWarehouseId: order.finishedGoodsWarehouseId,
          finishedGoodsWarehouseName: order.finishedGoodsWarehouseName,
          notes: order.notes,
          outputBatchAllocations: outputBatches ?? const <BatchAllocation>[],
          actualConsumedQuantities: consumed,
          wasteQuantities: waste,
          wasteReasons: wasteReasons,
        );
      } else {
        await widget.store.finishManufacturingOrder(
          orderId: order.id,
          actualQuantity: actualQuantity,
          outputBatchAllocations: outputBatches ?? const <BatchAllocation>[],
          actualConsumedQuantities: consumed,
          wasteQuantities: waste,
          wasteReasons: wasteReasons,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedErrorText(AppLocalizations.of(context), error),
          ),
        ),
      );
    } finally {
      qtyController.dispose();
      for (final controller in consumedControllers.values) {
        controller.dispose();
      }
      for (final controller in wasteControllers.values) {
        controller.dispose();
      }
      for (final controller in wasteReasonControllers.values) {
        controller.dispose();
      }
    }
  }
}
