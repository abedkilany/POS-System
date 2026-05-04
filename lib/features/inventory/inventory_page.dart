import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../widgets/summary_card.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});

  final AppStore store;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  String query = '';
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final products = widget.store.products.where((item) {
      final value = query.toLowerCase();
      return item.name.toLowerCase().contains(value) || item.code.toLowerCase().contains(value) || item.category.toLowerCase().contains(value);
    }).toList();

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [Tab(text: tr.text('inventory_overview')), Tab(text: tr.text('stock_movements'))],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InventoryOverview(store: widget.store, products: products, query: query, onQuery: (value) => setState(() => query = value), onAdjust: _openAdjustmentDialog),
              _MovementsList(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAdjustmentDialog(String productId) async {
    final tr = AppLocalizations.of(context);
    final product = widget.store.products.firstWhere((item) => item.id == productId);
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr.text('adjust_stock')} • ${product.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tr.text('current_stock')}: ${product.stock}'),
              const SizedBox(height: 12),
              TextField(controller: qtyController, decoration: InputDecoration(labelText: tr.text('quantity_delta'), helperText: tr.text('quantity_delta_help')), keyboardType: const TextInputType.numberWithOptions(signed: true)),
              const SizedBox(height: 12),
              TextField(controller: reasonController, decoration: InputDecoration(labelText: tr.text('reason'))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () async {
              final delta = int.tryParse(qtyController.text.trim()) ?? 0;
              if (delta == 0) return;
              try {
                await widget.store.adjustStock(productId: productId, quantityDelta: delta, reason: reasonController.text);
                if (context.mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              } catch (error) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
  }
}

class _InventoryOverview extends StatelessWidget {
  const _InventoryOverview({required this.store, required this.products, required this.query, required this.onQuery, required this.onAdjust});

  final AppStore store;
  final List<dynamic> products;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onAdjust;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(title: tr.text('product_count'), value: '${store.products.length}', icon: Icons.inventory_2_outlined),
            SummaryCard(title: tr.text('total_units'), value: '${store.totalUnitsInStock}', icon: Icons.layers_outlined),
            SummaryCard(title: tr.text('low_stock_alerts'), value: '${store.lowStockCount}', icon: Icons.warning_amber_rounded),
            SummaryCard(title: tr.text('inventory_value'), value: formatCurrency(store.inventoryRetailValue, currency: store.storeProfile.currency), icon: Icons.payments_outlined),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          decoration: InputDecoration(hintText: tr.text('search_inventory'), prefixIcon: const Icon(Icons.search)),
          onChanged: onQuery,
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(tr.text('inventory_overview'), style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(tr.text('inventory_page_desc')),
              ),
              const Divider(height: 1),
              if (products.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Text(tr.text('no_inventory_items')))
              else
                ...products.map((item) {
                  final isLow = item.stock <= item.lowStockThreshold;
                  return Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final meta = Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(formatCurrency(item.price, currency: store.storeProfile.currency)),
                              Chip(avatar: isLow ? const Icon(Icons.priority_high, size: 16) : null, label: Text('${tr.text('stock')}: ${item.stock}')),
                              TextButton.icon(onPressed: () => onAdjust(item.id), icon: const Icon(Icons.tune), label: Text(tr.text('adjust'))),
                            ],
                          );
                          if (constraints.maxWidth < 620) {
                            return ListTile(
                              leading: CircleAvatar(child: Icon(isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
                              title: Text(item.name),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${item.code} • ${item.category}'), const SizedBox(height: 6), meta]),
                            );
                          }
                          return ListTile(
                            leading: CircleAvatar(child: Icon(isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
                            title: Text(item.name),
                            subtitle: Text('${item.code} • ${item.category}'),
                            trailing: SizedBox(width: 360, child: Align(alignment: Alignment.centerRight, child: meta)),
                          );
                        },
                      ),
                      const Divider(height: 1),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final currency = store.storeProfile.currency;
    final movements = store.stockMovements;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: movements.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Text(tr.text('no_stock_movements')))
              : Column(
                  children: [
                    for (final movement in movements.take(200)) ...[
                      ListTile(
                        leading: CircleAvatar(child: Icon(movement.quantity >= 0 ? Icons.add : Icons.remove)),
                        title: Text(movement.productName),
                        subtitle: Text('${movement.type} • ${movement.referenceNo} • ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}'),
                        isThreeLine: true,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(movement.quantity > 0 ? '+${movement.quantity}' : '${movement.quantity}', style: Theme.of(context).textTheme.titleMedium),
                          if (movement.unitCost > 0) Text(formatCurrency(movement.value, currency: currency)),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
