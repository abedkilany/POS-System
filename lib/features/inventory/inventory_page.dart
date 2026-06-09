import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../widgets/summary_card.dart';
import '../barcode/barcode_scanner_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});

  final AppStore store;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  String query = '';
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _scanInventorySearchBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() {
      query = code.trim();
      _searchController.text = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final products = _filterProducts(widget.store.stockTrackedProducts, query);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [Tab(text: tr.text('inventory_overview')), Tab(text: tr.text('warehouses')), Tab(text: tr.text('stock_movements')), Tab(text: tr.text('waste_loss_report'))],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InventoryOverview(store: widget.store, products: products, query: query, searchController: _searchController, onScanBarcode: _scanInventorySearchBarcode, onQuery: (value) => setState(() => query = value), onAdjust: _openAdjustmentDialog),
              _WarehousesTab(store: widget.store),
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
  const _InventoryOverview({required this.store, required this.products, required this.query, required this.searchController, required this.onScanBarcode, required this.onQuery, required this.onAdjust});

  final AppStore store;
  final List<Product> products;
  final String query;
  final TextEditingController searchController;
  final VoidCallback onScanBarcode;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onAdjust;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final pageInsets = VentioResponsive.pageInsets(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: pageInsets,
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SummaryCard(title: tr.text('product_count'), value: '${store.products.length}', icon: Icons.inventory_2_outlined),
                  SummaryCard(title: tr.text('total_units'), value: '${store.totalUnitsInStock}', icon: Icons.layers_outlined),
                  SummaryCard(title: tr.text('low_stock_alerts'), value: '${store.lowStockCount}', icon: Icons.warning_amber_rounded),
                  SummaryCard(title: tr.text('inventory_value'), value: formatUsdReferenceAmount(store.inventoryRetailValue, store.storeProfile), icon: Icons.payments_outlined),
                  SummaryCard(title: 'Auto Corrections', value: '${store.stockMovements.where((m) => m.type == 'auto_correction').length}', icon: Icons.notifications_active_outlined),

                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: tr.text('search_inventory'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: tr.text('scan_with_camera'),
                    onPressed: onScanBarcode,
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                ),
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
                      Padding(padding: VentioResponsive.pageInsets(context), child: Text(tr.text('no_inventory_items'))),
                  ],
                ),
              ),
            ]),
          ),
        ),
        if (products.isNotEmpty)
          SliverPadding(
            padding: EdgeInsetsDirectional.only(
              start: pageInsets.left,
              end: pageInsets.right,
              bottom: pageInsets.bottom,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.crossAxisExtent < 620;
                return SliverFixedExtentList(
                  itemExtent: compact ? 128 : 82,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = products[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Card(
                          margin: EdgeInsets.zero,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          child: _InventoryProductTile(
                            product: product,
                            store: store,
                            compact: compact,
                            onAdjust: onAdjust,
                          ),
                        ),
                      );
                    },
                    childCount: products.length,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _InventoryProductTile extends StatelessWidget {
  const _InventoryProductTile({required this.product, required this.store, required this.compact, required this.onAdjust});

  final Product product;
  final AppStore store;
  final bool compact;
  final ValueChanged<String> onAdjust;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isLow = product.trackStock && product.stock <= product.lowStockThreshold;
    final meta = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(formatUsdReferenceAmount(product.price, store.storeProfile)),
        Chip(avatar: isLow ? const Icon(Icons.priority_high, size: 16) : null, label: Text('${tr.text('stock')}: ${product.stock}')),
        TextButton.icon(onPressed: () => onAdjust(product.id), icon: const Icon(Icons.tune), label: Text(tr.text('adjust'))),
      ],
    );
    if (compact) {
      return ListTile(
        leading: CircleAvatar(child: Icon(isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.code} • ${product.category}', maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            meta,
          ],
        ),
      );
    }
    return ListTile(
      leading: CircleAvatar(child: Icon(isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.code} • ${product.category}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 360, min: 180, horizontalPadding: 120)),
        child: Align(alignment: AlignmentDirectional.centerEnd, child: meta),
      ),
    );
  }
}

List<Product> _filterProducts(List<Product> products, String query) {
  final value = query.trim().toLowerCase();
  if (value.isEmpty) return products;
  return products.where((item) {
    return item.name.toLowerCase().contains(value) ||
        item.code.toLowerCase().contains(value) ||
        item.barcode.toLowerCase().contains(value) ||
        item.category.toLowerCase().contains(value) ||
        item.effectiveSaleUnits.any((unit) => unit.barcode.toLowerCase().contains(value)) ||
        item.effectivePurchaseUnits.any((unit) => unit.barcode.toLowerCase().contains(value));
  }).toList(growable: false);
}


class _WarehousesTab extends StatefulWidget {
  const _WarehousesTab({required this.store});
  final AppStore store;

  @override
  State<_WarehousesTab> createState() => _WarehousesTabState();
}

class _WarehousesTabState extends State<_WarehousesTab> {
  Future<void> _createWarehouse() async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final locationController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('create_warehouse')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('warehouse_name'))),
            const SizedBox(height: 12),
            TextField(controller: codeController, decoration: InputDecoration(labelText: tr.text('code_optional'))),
            const SizedBox(height: 12),
            TextField(controller: locationController, decoration: InputDecoration(labelText: tr.text('location_optional'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                await widget.store.createWarehouse(name: nameController.text, code: codeController.text, location: locationController.text);
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

  Future<void> _transferStock() async {
    final tr = AppLocalizations.of(context);
    final products = widget.store.stockTrackedProducts;
    final warehouses = widget.store.warehouses;
    if (products.isEmpty || warehouses.length < 2) return;
    var productId = products.first.id;
    var fromWarehouseId = warehouses.first.id;
    var toWarehouseId = warehouses.length > 1 ? warehouses[1].id : warehouses.first.id;
    final qtyController = TextEditingController();
    final notesController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('transfer_stock')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: productId,
                decoration: InputDecoration(labelText: tr.text('product')),
                items: products.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
                onChanged: (value) => setDialogState(() => productId = value ?? productId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: fromWarehouseId,
                decoration: InputDecoration(labelText: tr.text('from_warehouse')),
                items: warehouses.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
                onChanged: (value) => setDialogState(() => fromWarehouseId = value ?? fromWarehouseId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: toWarehouseId,
                decoration: InputDecoration(labelText: tr.text('to_warehouse')),
                items: warehouses.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
                onChanged: (value) => setDialogState(() => toWarehouseId = value ?? toWarehouseId),
              ),
              const SizedBox(height: 12),
              Text('${tr.text('available')}: ${widget.store.stockForWarehouse(productId, fromWarehouseId)}'),
              const SizedBox(height: 12),
              TextField(controller: qtyController, decoration: InputDecoration(labelText: tr.text('quantity')), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),
              TextField(controller: notesController, decoration: InputDecoration(labelText: tr.text('notes_optional'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.store.transferStock(productId: productId, fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, quantity: double.tryParse(qtyController.text.trim()) ?? 0, notes: notesController.text);
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

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final warehouses = widget.store.warehouses;
    final products = widget.store.stockTrackedProducts;
    final stockRowsByWarehouse = <String, List<_WarehouseProductStock>>{
      for (final warehouse in warehouses) warehouse.id: <_WarehouseProductStock>[],
    };
    for (final product in products) {
      for (final entry in widget.store.warehouseStockForProduct(product.id).entries) {
        if (entry.value != 0) {
          (stockRowsByWarehouse[entry.key] ??= <_WarehouseProductStock>[]).add(_WarehouseProductStock(product: product, stock: entry.value));
        }
      }
    }
    return ListView.builder(
      padding: VentioResponsive.pageInsets(context),
      itemCount: warehouses.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(onPressed: _createWarehouse, icon: const Icon(Icons.add_business_outlined), label: Text(tr.text('create_warehouse'))),
              OutlinedButton.icon(onPressed: warehouses.length < 2 ? null : _transferStock, icon: const Icon(Icons.swap_horiz), label: Text(tr.text('transfer_stock'))),
            ]),
          );
        }
        final warehouse = warehouses[index - 1];
        final rows = stockRowsByWarehouse[warehouse.id] ?? const <_WarehouseProductStock>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
            title: Text(warehouse.name),
            subtitle: Text([if (warehouse.code.isNotEmpty) warehouse.code, if (warehouse.location.isNotEmpty) warehouse.location].join(' • ')),
            children: [
              for (final row in rows.take(100))
                ListTile(
                  dense: true,
                  title: Text(row.product.name),
                  trailing: Text('${row.stock}'),
                ),
              if (rows.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr.text('no_inventory_items'))),
            ],
          ),
        );
      },
    );
  }
}

class _WarehouseProductStock {
  const _WarehouseProductStock({required this.product, required this.stock});

  final Product product;
  final double stock;
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
                        subtitle: Text("${movement.type} • ${movement.warehouseName} • ${movement.referenceNo} • ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}${movement.notes.isNotEmpty ? ' • ${movement.notes}' : ''}${movement.evidenceRef.isNotEmpty ? ' • ${tr.text('evidence')}: ${movement.evidenceRef}' : ''}"),
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
