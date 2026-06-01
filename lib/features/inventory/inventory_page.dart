import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
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
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final products = widget.store.stockTrackedProducts.where((item) {
      final value = query.toLowerCase();
      return item.name.toLowerCase().contains(value) || item.code.toLowerCase().contains(value) || item.category.toLowerCase().contains(value);
    }).toList();

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [Tab(text: tr.text('inventory_overview')), Tab(text: tr.text('stock_movements')), Tab(text: tr.text('waste_loss_report'))],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InventoryOverview(store: widget.store, products: products, query: query, onQuery: (value) => setState(() => query = value), onAdjust: _openAdjustmentDialog),
              _MovementsList(store: widget.store),
              _WasteLossReport(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAdjustmentDialog(String productId) async {
    final tr = AppLocalizations.of(context);
    final product = widget.store.stockTrackedProducts.firstWhere((item) => item.id == productId);
    final qtyController = TextEditingController();
    final notesController = TextEditingController();
    final evidenceController = TextEditingController();
    var category = 'damage';
    final categories = <String, String>{
      'damage': tr.text('adjustment_damage'),
      'expired': tr.text('adjustment_expired'),
      'free_sample': tr.text('adjustment_free_sample'),
      'internal_consumption': tr.text('adjustment_internal_consumption'),
      'stock_count_shortage': tr.text('adjustment_stock_count_shortage'),
      'stock_count_overage': tr.text('adjustment_stock_count_overage'),
      'other': tr.text('adjustment_other'),
    };
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${tr.text('adjust_stock')} • ${product.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${tr.text('current_stock')}: ${product.stock}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(labelText: tr.text('adjustment_reason_type')),
                  items: categories.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                  onChanged: (value) => setDialogState(() => category = value ?? category),
                ),
                const SizedBox(height: 12),
                TextField(controller: qtyController, decoration: InputDecoration(labelText: tr.text('quantity_delta'), helperText: tr.text('quantity_delta_help')), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true)),
                const SizedBox(height: 12),
                TextField(controller: notesController, decoration: InputDecoration(labelText: tr.text('notes_optional')), minLines: 1, maxLines: 3),
                const SizedBox(height: 12),
                TextField(controller: evidenceController, decoration: InputDecoration(labelText: tr.text('evidence_optional'), helperText: tr.text('evidence_optional_help'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () async {
                final delta = double.tryParse(qtyController.text.trim()) ?? 0;
                if (delta == 0) return;
                try {
                  await widget.store.adjustStock(
                    productId: productId,
                    quantityDelta: delta,
                    reason: categories[category] ?? category,
                    adjustmentCategory: category,
                    notes: notesController.text,
                    evidenceRef: evidenceController.text,
                  );
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
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(title: tr.text('product_count'), value: '${store.products.length}', icon: Icons.inventory_2_outlined),
            SummaryCard(title: tr.text('total_units'), value: '${store.totalUnitsInStock}', icon: Icons.layers_outlined),
            SummaryCard(title: tr.text('low_stock_alerts'), value: '${store.lowStockCount}', icon: Icons.warning_amber_rounded),
            SummaryCard(title: tr.text('inventory_value'), value: formatUsdReferenceAmount(store.inventoryRetailValue, store.storeProfile), icon: Icons.payments_outlined),
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
                Padding(padding: VentioResponsive.pageInsets(context), child: Text(tr.text('no_inventory_items')))
              else
                ...products.map((item) {
                  final isLow = item.trackStock && item.stock <= item.lowStockThreshold;
                  return Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final meta = Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(formatUsdReferenceAmount(item.price, store.storeProfile)),
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
                            trailing: ConstrainedBox(constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 360, min: 180, horizontalPadding: 120)), child: Align(alignment: AlignmentDirectional.centerEnd, child: meta)),
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
    final movements = store.stockMovements;
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Card(
          child: movements.isEmpty
              ? Padding(padding: VentioResponsive.pageInsets(context), child: Text(tr.text('no_stock_movements')))
              : Column(
                  children: [
                    for (final movement in movements.take(200)) ...[
                      ListTile(
                        leading: CircleAvatar(child: Icon(movement.quantity >= 0 ? Icons.add : Icons.remove)),
                        title: Text(movement.productName),
                        subtitle: Text("${movement.type} • ${movement.referenceNo} • ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}${movement.notes.isNotEmpty ? ' • ${movement.notes}' : ''}${movement.evidenceRef.isNotEmpty ? ' • ${tr.text('evidence')}: ${movement.evidenceRef}' : ''}"),
                        isThreeLine: true,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(movement.quantity > 0 ? '+${movement.quantity}' : '${movement.quantity}', style: Theme.of(context).textTheme.titleMedium),
                          if (movement.unitCost > 0) Text(formatUsdReferenceAmount(movement.value, store.storeProfile)),
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


class _WasteLossReport extends StatelessWidget {
  const _WasteLossReport({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final lossMovements = store.stockMovements.where((item) => item.type == 'inventory_loss' || (item.type == 'inventory_adjustment' && item.quantity < 0)).toList();
    final totals = <String, _WasteTotal>{};
    for (final movement in lossMovements) {
      final key = movement.adjustmentCategory.isEmpty ? 'other' : movement.adjustmentCategory;
      final current = totals[key] ?? _WasteTotal();
      current.quantity += movement.quantity.abs();
      current.value += movement.value;
      current.count += 1;
      totals[key] = current;
    }
    final totalValue = lossMovements.fold<double>(0, (sum, item) => sum + item.value);
    final totalQty = lossMovements.fold<double>(0, (sum, item) => sum + item.quantity.abs());
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(title: tr.text('loss_movements'), value: '${lossMovements.length}', icon: Icons.report_problem_outlined),
            SummaryCard(title: tr.text('loss_quantity'), value: totalQty.toStringAsFixed(totalQty.truncateToDouble() == totalQty ? 0 : 2), icon: Icons.remove_circle_outline),
            SummaryCard(title: tr.text('loss_value'), value: formatUsdReferenceAmount(totalValue, store.storeProfile), icon: Icons.money_off_outlined),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: totals.isEmpty
              ? Padding(padding: VentioResponsive.pageInsets(context), child: Text(tr.text('no_waste_loss_records')))
              : Column(
                  children: [
                    ListTile(title: Text(tr.text('waste_loss_by_reason'), style: Theme.of(context).textTheme.titleMedium)),
                    const Divider(height: 1),
                    for (final entry in totals.entries) ...[
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.category_outlined)),
                        title: Text(_adjustmentCategoryLabel(tr, entry.key)),
                        subtitle: Text('${tr.text('movements')}: ${entry.value.count} • ${tr.text('quantity')}: ${entry.value.quantity}'),
                        trailing: Text(formatUsdReferenceAmount(entry.value.value, store.storeProfile)),
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

class _WasteTotal {
  double quantity = 0;
  double value = 0;
  int count = 0;
}

String _adjustmentCategoryLabel(AppLocalizations tr, String key) {
  switch (key) {
    case 'damage':
      return tr.text('adjustment_damage');
    case 'expired':
      return tr.text('adjustment_expired');
    case 'free_sample':
      return tr.text('adjustment_free_sample');
    case 'internal_consumption':
      return tr.text('adjustment_internal_consumption');
    case 'stock_count_shortage':
      return tr.text('adjustment_stock_count_shortage');
    case 'stock_count_overage':
      return tr.text('adjustment_stock_count_overage');
    default:
      return tr.text('adjustment_other');
  }
}
