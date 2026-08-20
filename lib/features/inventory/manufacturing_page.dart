// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/services/manufacturing_pdf_service.dart';

import '../../data/app_store.dart';
import '../../models/manufacturing.dart';
import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import 'batch_allocation_dialog.dart';

class ManufacturingPage extends StatefulWidget {
  const ManufacturingPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ManufacturingPage> createState() => _ManufacturingPageState();
}

class _ManufacturingPageState extends State<ManufacturingPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedOrderIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) =>
      AppLocalizations.of(context).format(key, values);
  @override
  Widget build(BuildContext context) {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) {
      return _AccessDeniedScaffold(
        title: _t('manufacturing_orders'),
        message: _t('no_access_manufacturing_tools'),
      );
    }
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final query = _searchQuery.trim().toLowerCase();
        final boms = widget.store.billsOfMaterials.where((bom) {
          if (query.isEmpty) return true;
          return <String>[
            bom.name,
            bom.outputProductName,
            bom.notes,
            ...bom.components.map((item) => item.productName),
          ].any((value) => value.toLowerCase().contains(query));
        }).toList(growable: false);
        final orders = widget.store.manufacturingOrders.where((order) {
          if (query.isEmpty) return true;
          return <String>[
            order.orderNo,
            order.bomName,
            order.outputProductName,
            order.status,
            order.rawMaterialsWarehouseName,
            order.finishedGoodsWarehouseName,
            order.notes,
          ].any((value) => value.toLowerCase().contains(query));
        }).toList(growable: false);

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_t('manufacturing_page')),
              bottom: TabBar(
                tabs: [
                  Tab(
                    icon: const Icon(Icons.account_tree_outlined),
                    text: _t('bills_of_materials'),
                  ),
                  Tab(
                    icon: const Icon(Icons.precision_manufacturing_outlined),
                    text: _t('manufacturing_orders'),
                  ),
                ],
              ),
            ),
            body: Builder(
              builder: (tabContext) {
                final tabController = DefaultTabController.of(tabContext);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    final isRecipesTab = tabController.index == 0;
                    return Column(
                      children: [
                        if (isRecipesTab)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                ),
                                onPressed:
                                    widget.store.hasAnyPermission(<String>{
                                  AppPermission.inventoryManufacturingManage,
                                  AppPermission.productsEdit,
                                })
                                        ? () => _showBomDialog()
                                        : null,
                                icon: const Icon(Icons.add),
                                label: Text(_t('new_bom')),
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            isRecipesTab ? 0 : 16,
                            16,
                            8,
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: _localizedText(
                                ar: 'بحث في التصنيع',
                                en: 'Search manufacturing',
                                fr: 'Rechercher dans la fabrication',
                              ),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: _localizedText(
                                        ar: 'مسح البحث',
                                        en: 'Clear search',
                                        fr: 'Effacer la recherche',
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildRecipesTab(boms),
                              _buildOrdersTab(orders),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

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
                subtitle: Text(_tf('bom_subtitle', {
                  'product': bom.outputProductName,
                  'output': bom.outputQuantity,
                  'components': bom.components.length,
                  'cost': bom.unitCost.toStringAsFixed(2),
                })),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _localizedText(ar: 'طباعة', en: 'Print', fr: 'Imprimer'),
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
                    Tooltip(
                      message: <String>{'completed', 'complete'}.contains(order.status.toLowerCase())
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
                        onPressed: <String>{'completed', 'complete'}.contains(order.status.toLowerCase())
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
                title: Text(order.orderNo),
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
      default:
        return null;
    }
  }

  Future<void> _printBom(BillOfMaterials bom) async {
    try {
      await ManufacturingPdfService.printBillOfMaterials(
        bom: bom,
        profile: widget.store.storeProfile,
        locale: Localizations.localeOf(context),
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
        for (final bom in widget.store.billsOfMaterials) bom.id: bom,
      };
      await ManufacturingPdfService.printManufacturingOrders(
        orders: selectedOrders,
        bomsById: bomsById,
        includeDetails: includeDetails,
        profile: widget.store.storeProfile,
        locale: Localizations.localeOf(context),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showBomDialog({BillOfMaterials? bom}) async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) {
      return;
    }
    final products = widget.store.stockTrackedProducts;
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
      matches.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                      label: _localizedText(ar: 'منتج الوصفة', en: 'Recipe product', fr: 'Produit de la recette'),
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
        await widget.store.createBillOfMaterials(
          name: nameController.text,
          outputProductId: selectedOutput.id,
          outputQuantity: double.tryParse(outputQtyController.text) ?? 1,
          components: components,
        );
      } else {
        await widget.store.updateBillOfMaterials(
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
      await widget.store.deleteBillOfMaterials(bom.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<void> _showCompleteOrderDialog(BillOfMaterials bom) async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) return;
    final qtyController =
        TextEditingController(text: bom.outputQuantity.toString());
    final warehouses = widget.store.warehouses;
    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('warehouse_not_found'))),
      );
      return;
    }
    var rawWarehouseId = widget.store.resolveWarehouseForPurchase().id;
    var finishedWarehouseId = widget.store.resolveWarehouseForSale().id;
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
            final available = widget.store
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
      await widget.store.startManufacturingOrder(
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
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) {
      return;
    }
    if (<String>{'completed', 'complete'}.contains(order.status.trim().toLowerCase())) return;

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
      await widget.store.deleteManufacturingOrder(order.id);
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

  Future<void> _showFinishOrderDialog(ManufacturingOrder order) async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) return;

    final qtyController = TextEditingController(text: order.quantity.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          ar: 'تأكيد انتهاء التصنيع',
          en: 'Confirm production completion',
          fr: 'Confirmer la fin de fabrication',
        )),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.outputProductName),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.task_alt),
            label: Text(_localizedText(
              ar: 'تأكيد الانتهاء',
              en: 'Confirm completion',
              fr: 'Confirmer la fin',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

      await widget.store.finishManufacturingOrder(
        orderId: order.id,
        actualQuantity: actualQuantity,
        outputBatchAllocations: outputBatches ?? const <BatchAllocation>[],
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
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              Text(value, style: Theme.of(context).textTheme.headlineSmall)
            ])
          ],
        ),
      ),
    );
  }
}
