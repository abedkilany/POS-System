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

class _InventoryPageState extends State<InventoryPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final products = widget.store.products.where((item) {
      final value = query.toLowerCase();
      return item.name.toLowerCase().contains(value) || item.code.toLowerCase().contains(value) || item.category.toLowerCase().contains(value);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(title: tr.text('product_count'), value: '${widget.store.products.length}', icon: Icons.inventory_2_outlined),
            SummaryCard(title: tr.text('total_units'), value: '${widget.store.totalUnitsInStock}', icon: Icons.layers_outlined),
            SummaryCard(title: tr.text('low_stock_alerts'), value: '${widget.store.lowStockCount}', icon: Icons.warning_amber_rounded),
            SummaryCard(title: tr.text('inventory_value'), value: formatCurrency(widget.store.inventoryRetailValue, currency: widget.store.storeProfile.currency), icon: Icons.payments_outlined),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          decoration: InputDecoration(hintText: tr.text('search_inventory'), prefixIcon: const Icon(Icons.search)),
          onChanged: (value) => setState(() => query = value),
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
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr.text('no_inventory_items')),
                )
              else
                ...products.map((item) {
                  final isLow = item.stock <= 5;
                  return Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(child: Icon(isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
                        title: Text(item.name),
                        subtitle: Text('${item.code} • ${item.category}'),
                        trailing: SizedBox(
                          width: 260,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(formatCurrency(item.price, currency: widget.store.storeProfile.currency)),
                              const SizedBox(width: 12),
                              Chip(
                                avatar: isLow ? const Icon(Icons.priority_high, size: 16) : null,
                                label: Text('${tr.text('stock')}: ${item.stock}'),
                              ),
                            ],
                          ),
                        ),
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
