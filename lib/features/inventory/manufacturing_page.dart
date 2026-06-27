// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';

import '../../data/app_store.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';

class ManufacturingPage extends StatefulWidget {
  const ManufacturingPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ManufacturingPage> createState() => _ManufacturingPageState();
}

class _ManufacturingPageState extends State<ManufacturingPage> {
  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) => AppLocalizations.of(context).format(key, values);
  @override
  Widget build(BuildContext context) {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) {
      return const _AccessDeniedScaffold(
        title: 'Manufacturing',
        message: 'You do not have access to manufacturing tools.',
      );
    }
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final boms = widget.store.billsOfMaterials;
        final orders = widget.store.manufacturingOrders;
        return Scaffold(
          appBar: AppBar(title: Text(_t('manufacturing_page'))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: widget.store.hasAnyPermission(<String>{
                  AppPermission.inventoryManufacturingManage,
                  AppPermission.productsEdit,
                })
                ? _showCreateBomDialog
                : null,
            icon: const Icon(Icons.add),
            label: Text(_t('new_bom')),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _SummaryCard(title: _t('boms'), value: boms.length.toString(), icon: Icons.account_tree_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: _t('orders'), value: orders.length.toString(), icon: Icons.precision_manufacturing_outlined)),
                ],
              ),
              const SizedBox(height: 16),
              Text(_t('bills_of_materials'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (boms.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_t('no_manufacturing_recipes')))))
              else
                ...boms.map((bom) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(bom.name),
                        subtitle: Text(_tf('bom_subtitle', {'product': bom.outputProductName, 'output': bom.outputQuantity, 'components': bom.components.length, 'cost': bom.unitCost.toStringAsFixed(2)})),
                        trailing: FilledButton.icon(
                          onPressed: () => _showCompleteOrderDialog(bom),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_t('produce')),
                        ),
                      ),
                    )),
              const SizedBox(height: 24),
              Text(_t('manufacturing_orders'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (orders.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_t('no_manufacturing_orders')))))
              else
                ...orders.map((order) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.precision_manufacturing_outlined),
                        title: Text(order.orderNo),
                        subtitle: Text(_tf('order_subtitle', {'product': order.outputProductName, 'qty': order.quantity, 'status': order.status})),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateBomDialog() async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) {
      return;
    }
    final products = widget.store.products.where((p) => p.trackStock).toList();
    if (products.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('create_two_stock_products_first'))));
      return;
    }
    Product output = products.first;
    final nameController = TextEditingController(text: 'BOM - ${output.name}');
    final outputQtyController = TextEditingController(text: '1');
    final componentProductIds = <String>[products.length > 1 ? products[1].id : products.first.id];
    final componentQtyControllers = <TextEditingController>[TextEditingController(text: '1')];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('new_bom')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: InputDecoration(labelText: _t('bom_name'))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: output.id,
                    decoration: InputDecoration(labelText: _t('output_product')),
                    items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (value) {
                      final selected = products.firstWhere((p) => p.id == value);
                      setDialogState(() {
                        output = selected;
                        for (var i = 0; i < componentProductIds.length; i += 1) {
                          if (componentProductIds[i] == output.id) {
                            componentProductIds[i] = products.firstWhere((p) => p.id != output.id).id;
                          }
                        }
                        nameController.text = 'BOM - ${selected.name}';
                      });
                    },
                  ),
                  TextField(controller: outputQtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _t('output_quantity'))),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: Text(_t('components'), style: Theme.of(context).textTheme.titleMedium)),
                  ...List.generate(componentProductIds.length, (index) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: componentProductIds[index],
                            items: products.where((p) => p.id != output.id).map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                            onChanged: (value) => setDialogState(() => componentProductIds[index] = value ?? componentProductIds[index]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: componentQtyControllers[index], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _t('qty')))),
                        IconButton(
                          onPressed: componentProductIds.length == 1 ? null : () => setDialogState(() { componentProductIds.removeAt(index); componentQtyControllers.removeAt(index); }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setDialogState(() { componentProductIds.add(products.firstWhere((p) => p.id != output.id).id); componentQtyControllers.add(TextEditingController(text: '1')); }),
                    icon: const Icon(Icons.add),
                    label: Text(_t('add_component')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t('save'))),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final components = <BillOfMaterialsLine>[];
      for (var i = 0; i < componentProductIds.length; i++) {
        final product = products.firstWhere((p) => p.id == componentProductIds[i]);
        components.add(BillOfMaterialsLine(productId: product.id, productName: product.name, quantity: double.tryParse(componentQtyControllers[i].text) ?? 0, unitCost: product.usdCost));
      }
      await widget.store.createBillOfMaterials(
        name: nameController.text,
        outputProductId: output.id,
        outputQuantity: double.tryParse(outputQtyController.text) ?? 1,
        components: components,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showCompleteOrderDialog(BillOfMaterials bom) async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryManufacturingManage,
      AppPermission.productsEdit,
    })) return;
    final qtyController = TextEditingController(text: bom.outputQuantity.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tf('produce_product', {'product': bom.outputProductName})),
        content: TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _t('quantity_to_produce'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t('complete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.completeManufacturingOrder(bomId: bom.id, quantity: double.tryParse(qtyController.text) ?? 0);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
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
  const _SummaryCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [Icon(icon), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), Text(value, style: Theme.of(context).textTheme.headlineSmall)])],
        ),
      ),
    );
  }
}
