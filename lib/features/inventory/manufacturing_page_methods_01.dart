// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: curly_braces_in_flow_control_structures
part of 'manufacturing_page.dart';

extension _ManufacturingPageStatePart1 on _ManufacturingPageState {
  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) =>
      AppLocalizations.of(context).format(key, values);

  Widget _buildRecipesTab(List<BillOfMaterials> boms) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _SummaryCard(
          title: _t('boms'),
          value: boms.length.toString(),
          icon: Icons.account_tree_outlined,
        ),
        const SizedBox(height: 12),
        if (boms.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(_t('no_manufacturing_recipes'))),
            ),
          )
        else
          ...boms.map(
            (bom) => Card(
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(bom.name),
                subtitle: FutureBuilder<double>(
                  future: widget.store.inventory
                      .estimateBillOfMaterialsUnitCost(bom),
                  initialData: bom.unitCost,
                  builder: (context, snapshot) {
                    final estimatedCost = snapshot.data ?? bom.unitCost;
                    return Text(_tf('bom_subtitle', {
                      'product': bom.outputProductName,
                      'output': bom.outputQuantity,
                      'components': bom.components.length,
                      'cost': estimatedCost.toStringAsFixed(2),
                    }));
                  },
                ),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _localizedText(
                          ar: 'طباعة', en: 'Print', fr: 'Imprimer'),
                      onPressed: () => _printBom(bom),
                      icon: const Icon(Icons.print_outlined),
                    ),
                    IconButton(
                      tooltip: _t('edit'),
                      onPressed: () => _showBomDialog(bom: bom),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: _t('delete'),
                      onPressed: () => _confirmDeleteBom(bom),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCompleteOrderDialog(bom),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_t('produce')),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOrdersTab(List<ManufacturingOrder> orders) {
    final visibleOrderIds = orders.map((order) => order.id).toSet();
    final selectedVisibleCount =
        _selectedOrderIds.where(visibleOrderIds.contains).length;
    final allVisibleSelected =
        orders.isNotEmpty && selectedVisibleCount == orders.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _SummaryCard(
          title: _t('orders'),
          value: orders.length.toString(),
          icon: Icons.precision_manufacturing_outlined,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Checkbox(
                  value: selectedVisibleCount == 0
                      ? false
                      : allVisibleSelected
                          ? true
                          : null,
                  tristate: true,
                  onChanged: orders.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selectedOrderIds.addAll(visibleOrderIds);
                            } else {
                              _selectedOrderIds.removeAll(visibleOrderIds);
                            }
                          });
                        },
                ),
                Text(_localizedText(
                  ar: 'تحديد الكل',
                  en: 'Select all',
                  fr: 'Tout sélectionner',
                )),
                const SizedBox(width: 4),
                Text(_localizedText(
                  ar: 'المحدد: $selectedVisibleCount',
                  en: 'Selected: $selectedVisibleCount',
                  fr: 'Sélectionnés : $selectedVisibleCount',
                )),
                FilledButton.icon(
                  onPressed: selectedVisibleCount == 0
                      ? null
                      : () => _printSelectedOrders(orders),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_localizedText(
                    ar: 'طباعة المحدد',
                    en: 'Print selected',
                    fr: 'Imprimer la sélection',
                  )),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(_t('no_manufacturing_orders'))),
            ),
          )
        else
          ...orders.map((order) {
            return Card(
              child: CheckboxListTile(
                value: _selectedOrderIds.contains(order.id),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedOrderIds.add(order.id);
                    } else {
                      _selectedOrderIds.remove(order.id);
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                secondary: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (order.status.toLowerCase() == 'in_progress') ...[
                      FilledButton.icon(
                        onPressed: () => _showFinishOrderDialog(order),
                        icon: const Icon(Icons.task_alt),
                        label: Text(_localizedText(
                          ar: 'تأكيد الانتهاء',
                          en: 'Confirm completion',
                          fr: 'Confirmer la fin',
                        )),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (<String>{'completed', 'complete'}
                        .contains(order.status.toLowerCase())) ...[
                      OutlinedButton.icon(
                        onPressed: () => _reverseManufacturingOrder(order),
                        icon: const Icon(Icons.undo),
                        label: Text(_localizedText(
                          ar: 'عكس',
                          en: 'Reverse',
                          fr: 'Contrepasser',
                        )),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: _localizedText(
                        ar: 'تعديل أمر التصنيع',
                        en: 'Edit manufacturing order',
                        fr: 'Modifier l’ordre de fabrication',
                      ),
                      onPressed: order.status.toLowerCase() == 'in_progress'
                          ? () => _showEditOrderDialog(order)
                          : <String>{'completed', 'complete'}
                                  .contains(order.status.toLowerCase())
                              ? () => _showFinishOrderDialog(
                                    order,
                                    editCompleted: true,
                                  )
                              : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Tooltip(
                      message: <String>{
                        'completed',
                        'complete',
                        'reversed',
                        'posted'
                      }.contains(order.status.toLowerCase())
                          ? _localizedText(
                              ar: 'لا يمكن حذف أمر مكتمل لأن حركات المخزون تم ترحيلها',
                              en: 'Completed orders cannot be deleted because inventory movements are already posted',
                              fr: 'Un ordre terminé ne peut pas être supprimé car les mouvements de stock sont déjà validés',
                            )
                          : _localizedText(
                              ar: 'حذف أمر التصنيع',
                              en: 'Delete manufacturing order',
                              fr: 'Supprimer l’ordre de fabrication',
                            ),
                      child: OutlinedButton.icon(
                        onPressed: <String>{
                          'completed',
                          'complete',
                          'reversed',
                          'posted'
                        }.contains(order.status.toLowerCase())
                            ? null
                            : () => _confirmDeleteManufacturingOrder(order),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(_localizedText(
                          ar: 'حذف',
                          en: 'Delete',
                          fr: 'Supprimer',
                        )),
                      ),
                    ),
                  ],
                ),
                title: InkWell(
                  onTap: () => _showOrderDetails(order),
                  child: Text(order.orderNo),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_localizedText(
                      ar: '${order.outputProductName} • الكمية: ${order.quantity}',
                      en: '${order.outputProductName} • Qty: ${order.quantity}',
                      fr: '${order.outputProductName} • Qté : ${order.quantity}',
                    )),
                    const SizedBox(height: 4),
                    Text(
                      _manufacturingStatusLabel(order.status),
                      style: TextStyle(
                        color: _manufacturingStatusColor(order.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  String _localizedText({required String ar, required String en, String? fr}) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'ar':
        return ar;
      case 'fr':
        return fr ?? en;
      default:
        return en;
    }
  }

  String _manufacturingStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'in_progress':
        return _localizedText(
          ar: 'قيد التصنيع',
          en: 'In production',
          fr: 'En fabrication',
        );
      case 'completed':
        return _localizedText(
          ar: 'مكتمل',
          en: 'Completed',
          fr: 'Terminé',
        );
      case 'reversed':
        return _localizedText(
          ar: 'معكوس',
          en: 'Reversed',
          fr: 'Contrepassé',
        );
      default:
        return status;
    }
  }

  Color? _manufacturingStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'reversed':
        return Colors.red;
      default:
        return null;
    }
  }

  Future<void> _printBom(BillOfMaterials bom) async {
    final locale = Localizations.localeOf(context);
    try {
      final estimatedBom =
          await widget.store.inventory.estimateBillOfMaterialsSnapshot(bom);
      if (!mounted) return;
      await ManufacturingPdfService.printBillOfMaterials(
        bom: estimatedBom,
        profile: widget.store.runtime.profile,
        context: context,
        locale: locale,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _printSelectedOrders(
      List<ManufacturingOrder> visibleOrders) async {
    final selectedOrders = visibleOrders
        .where((order) => _selectedOrderIds.contains(order.id))
        .toList(growable: false);
    if (selectedOrders.isEmpty) return;

    var includeDetails = false;
    final shouldPrint = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_localizedText(
                ar: 'خيارات الطباعة',
                en: 'Print options',
                fr: 'Options d’impression',
              )),
              content: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeDetails,
                onChanged: (value) {
                  setDialogState(() => includeDetails = value ?? false);
                },
                title: Text(_localizedText(
                  ar: 'إظهار تفاصيل الوصفة',
                  en: 'Show recipe details',
                  fr: 'Afficher les détails de la recette',
                )),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_localizedText(
                    ar: 'إلغاء',
                    en: 'Cancel',
                    fr: 'Annuler',
                  )),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_localizedText(
                    ar: 'طباعة',
                    en: 'Print',
                    fr: 'Imprimer',
                  )),
                ),
              ],
            );
          },
        );
      },
    );
    if (shouldPrint != true || !mounted) return;

    try {
      final bomsById = <String, BillOfMaterials>{
        for (final bom in widget.store.inventory.billsOfMaterials) bom.id: bom,
      };
      await ManufacturingPdfService.printManufacturingOrders(
        orders: selectedOrders,
        bomsById: bomsById,
        includeDetails: includeDetails,
        profile: widget.store.runtime.profile,
        context: context,
        locale: Localizations.localeOf(context),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}
