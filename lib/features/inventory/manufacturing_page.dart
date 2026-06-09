import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';

class ManufacturingPage extends StatefulWidget {
  const ManufacturingPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ManufacturingPage> createState() => _ManufacturingPageState();
}

class _ManufacturingPageState extends State<ManufacturingPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final boms = widget.store.billsOfMaterials;
        final orders = widget.store.manufacturingOrders;
        return Scaffold(
          appBar: AppBar(title: const Text('Manufacturing')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showCreateBomDialog,
            icon: const Icon(Icons.add),
            label: const Text('New BOM'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _SummaryCard(title: 'BOMs', value: boms.length.toString(), icon: Icons.account_tree_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Orders', value: orders.length.toString(), icon: Icons.precision_manufacturing_outlined)),
                ],
              ),
              const SizedBox(height: 16),
              Text('Bills of Materials', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (boms.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No manufacturing recipes yet.'))))
              else
                ...boms.map((bom) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(bom.name),
                        subtitle: Text('${bom.outputProductName} • output ${bom.outputQuantity} • components ${bom.components.length} • unit cost ${bom.unitCost.toStringAsFixed(2)}'),
                        trailing: FilledButton.icon(
                          onPressed: () => _showCompleteOrderDialog(bom),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Produce'),
                        ),
                      ),
                    )),
              const SizedBox(height: 24),
              Text('Manufacturing Orders', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (orders.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No manufacturing orders yet.'))))
              else
                ...orders.map((order) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.precision_manufacturing_outlined),
                        title: Text(order.orderNo),
                        subtitle: Text('${order.outputProductName} • qty ${order.quantity} • ${order.status}'),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateBomDialog() async {
    final products = widget.store.products.where((p) => p.trackStock).toList();
    if (products.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create at least two stock-tracked products first.')));
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
          title: const Text('New BOM'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'BOM name')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: output.id,
                    decoration: const InputDecoration(labelText: 'Output product'),
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
                  TextField(controller: outputQtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Output quantity')),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: Text('Components', style: Theme.of(context).textTheme.titleMedium)),
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
                        Expanded(child: TextField(controller: componentQtyControllers[index], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
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
                    label: const Text('Add component'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
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
    final qtyController = TextEditingController(text: bom.outputQuantity.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Produce ${bom.outputProductName}'),
        content: TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity to produce')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Complete')),
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
