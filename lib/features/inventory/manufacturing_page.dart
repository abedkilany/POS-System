// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/business_revision_service.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/local_database_service.dart';
import '../../data/app_store.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import '../../widgets/summary_card.dart';

class ManufacturingPage extends StatefulWidget {
  const ManufacturingPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ManufacturingPage> createState() => _ManufacturingPageState();
}

class _ManufacturingPageState extends State<ManufacturingPage> {
  Future<List<BillOfMaterials>?>? _bomsFuture;
  Future<List<ManufacturingOrder>?>? _ordersFuture;
  String _futureKey = '';

  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) =>
      AppLocalizations.of(context).format(key, values);

  Future<void> _loadData() async {
    final key =
        '${BusinessRevisionService.instance.inventoryRevision}|manufacturing';
    if (_futureKey == key && _bomsFuture != null && _ordersFuture != null) {
      return;
    }
    _futureKey = key;
    _bomsFuture = InventoryRepository.getBillOfMaterials();
    _ordersFuture = InventoryRepository.getManufacturingOrders();
  }

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
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return FutureBuilder<void>(
      future: _loadData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        return FutureBuilder<List<BillOfMaterials>?>(
          future: _bomsFuture,
          builder: (context, bomsSnapshot) {
            return FutureBuilder<List<ManufacturingOrder>?>(
              future: _ordersFuture,
              builder: (context, ordersSnapshot) {
                final boms = bomsSnapshot.data ?? const <BillOfMaterials>[];
                final orders =
                    ordersSnapshot.data ?? const <ManufacturingOrder>[];
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
                          Expanded(
                            child: SummaryCard(
                              title: _t('boms'),
                              value: boms.length.toString(),
                              icon: Icons.account_tree_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SummaryCard(
                              title: _t('orders'),
                              value: orders.length.toString(),
                              icon: Icons.precision_manufacturing_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(_t('bills_of_materials'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (boms.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(_t('no_manufacturing_recipes')),
                            ),
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
                                'cost': bom.unitCost.toStringAsFixed(2)
                              })),
                              trailing: FilledButton.icon(
                                onPressed: () => _showCompleteOrderDialog(bom),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(_t('produce')),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(_t('manufacturing_orders'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (orders.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text(_t('no_manufacturing_orders'))),
                          ),
                        )
                      else
                        ...orders.map(
                          (order) => Card(
                            child: ListTile(
                              leading:
                                  const Icon(Icons.precision_manufacturing_outlined),
                              title: Text(order.orderNo),
                              subtitle: Text(_tf('order_subtitle', {
                                'product': order.outputProductName,
                                'qty': order.quantity,
                                'status': order.status
                              })),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
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
    final productPage = await ProductRepository.queryPage(
      limit: 500,
      stockTrackedOnly: true,
    );
    if (!mounted) return;
    final products = productPage?.items ?? const <Product>[];
    if (products.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('create_two_stock_products_first'))),
      );
      return;
    }
    final productById = {for (final product in products) product.id: product};
    final productItems = [
      for (final product in products)
        DropdownMenuItem(
          value: product.id,
          child: Text(product.name),
        ),
    ];
    List<DropdownMenuItem<String>> componentItemsFor(String outputId) {
      return [
        for (final product in products)
          if (product.id != outputId)
            DropdownMenuItem(
              value: product.id,
              child: Text(product.name),
            ),
      ];
    }

    Product firstAlternativeProduct(String excludedId) {
      for (final product in products) {
        if (product.id != excludedId) return product;
      }
      return products.first;
    }

    Product output = products.first;
    final nameController = TextEditingController(text: 'BOM - ${output.name}');
    final outputQtyController = TextEditingController(text: '1');
    final componentProductIds = <String>[firstAlternativeProduct(output.id).id];
    final componentQtyControllers = <TextEditingController>[
      TextEditingController(text: '1')
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final componentItems = componentItemsFor(output.id);
          return AlertDialog(
            title: Text(_t('new_bom')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: nameController,
                        decoration: InputDecoration(labelText: _t('bom_name'))),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: output.id,
                      decoration:
                          InputDecoration(labelText: _t('output_product')),
                      items: productItems,
                      onChanged: (value) {
                        final selected = value == null ? null : productById[value];
                        if (selected == null) return;
                        setDialogState(() {
                          output = selected;
                          final replacementId =
                              firstAlternativeProduct(output.id).id;
                          for (var i = 0; i < componentProductIds.length; i += 1) {
                            if (componentProductIds[i] == output.id) {
                              componentProductIds[i] = replacementId;
                            }
                          }
                          nameController.text = 'BOM - ${selected.name}';
                        });
                      },
                    ),
                    TextField(
                        controller: outputQtyController,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: _t('output_quantity'))),
                    const SizedBox(height: 16),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_t('components'),
                            style: Theme.of(context).textTheme.titleMedium)),
                    ...List.generate(componentProductIds.length, (index) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: componentProductIds[index],
                              items: componentItems,
                              onChanged: (value) => setDialogState(() =>
                                  componentProductIds[index] =
                                      value ?? componentProductIds[index]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: componentQtyControllers[index],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: _t('qty')),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: componentProductIds.length <= 1
                                ? null
                                : () => setDialogState(() {
                                      componentProductIds.removeAt(index);
                                      componentQtyControllers.removeAt(index)
                                          .dispose();
                                    }),
                          )
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setDialogState(() {
                        componentProductIds.add(firstAlternativeProduct(output.id).id);
                        componentQtyControllers
                            .add(TextEditingController(text: '1'));
                      }),
                      icon: const Icon(Icons.add),
                      label: Text(_t('add_component')),
                    )
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
                child: Text(_t('save')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      nameController.dispose();
      outputQtyController.dispose();
      for (final controller in componentQtyControllers) {
        controller.dispose();
      }
      return;
    }
    nameController.dispose();
    outputQtyController.dispose();
    for (final controller in componentQtyControllers) {
      controller.dispose();
    }
  }

  Future<void> _showCompleteOrderDialog(BillOfMaterials bom) async {}
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
