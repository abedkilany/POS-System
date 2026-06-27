import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import '../../widgets/summary_card.dart';
import '../barcode/barcode_scanner_page.dart';

String _movementTypeLabel(AppLocalizations tr, String type) {
  switch (type) {
    case 'auto_correction':
      return tr.text('auto_correction');
    case 'purchase_receive':
      return tr.text('purchase_received');
    case 'purchase_return':
      return tr.text('purchase_return');
    case 'purchase_cancel':
      return tr.text('purchase_cancel');
    case 'sale':
      return tr.text('sale_invoice');
    case 'sale_return':
      return tr.text('return_sale');
    case 'sale_restore':
      return tr.text('sale_restore');
    case 'sale_cancel':
      return tr.text('sale_cancel');
    case 'paymentReceived':
      return tr.text('payment_received');
    case 'paymentPaid':
      return tr.text('payment_paid');
    case 'paymentReversal':
      return tr.text('payment_reversal');
    case 'warehouse_transfer_in':
      return tr.text('warehouse_transfer_in');
    case 'warehouse_transfer_out':
      return tr.text('warehouse_transfer_out');
    case 'count_adjustment':
      return tr.text('count_adjustment');
    case 'manufacturing_consume':
      return tr.text('manufacturing_consume');
    case 'manufacturing_output':
      return tr.text('manufacturing_output');
    default:
      return type.replaceAll('_', ' ');
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});

  final AppStore store;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  String query = '';
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController =
      TabController(length: 6, vsync: this);

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
    if (!widget.store.canViewInventory) {
      return _InventoryAccessDenied(
        title: tr.text('inventory'),
        message: 'This section is not available for your current role.',
      );
    }
    final products = _filterProducts(widget.store.stockTrackedProducts, query);
    final canViewOverview = widget.store.hasPermission(AppPermission.inventoryView) ||
        widget.store.hasPermission(AppPermission.reportsView) ||
        widget.store.hasPermission(AppPermission.productsCreate) ||
        widget.store.hasPermission(AppPermission.productsEdit) ||
        widget.store.hasPermission(AppPermission.productsDelete);
    final canManageWarehouses = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWarehousesManage,
      AppPermission.productsEdit,
    });
    final canViewMovements = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });
    final canViewCorrections = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });
    final canManageCounts = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCountsManage,
      AppPermission.productsEdit,
    });
    final canViewWasteLoss = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });

    if (!canViewOverview &&
        !canManageWarehouses &&
        !canViewMovements &&
        !canViewCorrections &&
        !canManageCounts &&
        !canViewWasteLoss) {
      return _InventoryAccessDenied(
        title: tr.text('inventory'),
        message: 'This section is not available for your current role.',
      );
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: tr.text('inventory_overview')),
              Tab(text: tr.text('warehouses')),
              Tab(text: tr.text('stock_movements')),
              Tab(text: tr.text('auto_corrections')),
              Tab(text: tr.text('stock_count')),
              Tab(text: tr.text('waste_loss_report')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InventoryOverview(
                store: widget.store,
                products: products,
                query: query,
                searchController: _searchController,
                onScanBarcode: _scanInventorySearchBarcode,
                onQuery: (value) => setState(() => query = value),
                onAdjust: canManageCounts ? _openAdjustmentDialog : null,
                canAdjust: canManageCounts,
              ),
              _WarehousesTab(store: widget.store),
              _MovementsList(store: widget.store),
              _AutoCorrectionsTab(store: widget.store),
              _StockCountTab(store: widget.store),
              _WasteLossReport(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAdjustmentDialog(String productId) async {
    final tr = AppLocalizations.of(context);
    final product = widget.store.stockTrackedProducts
        .firstWhere((item) => item.id == productId);
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
                  decoration: InputDecoration(
                      labelText: tr.text('adjustment_reason_type')),
                  items: categories.entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => category = value ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: qtyController,
                    decoration: InputDecoration(
                        labelText: tr.text('quantity_delta'),
                        helperText: tr.text('quantity_delta_help')),
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: notesController,
                    decoration:
                        InputDecoration(labelText: tr.text('notes_optional')),
                    minLines: 1,
                    maxLines: 3),
                const SizedBox(height: 12),
                TextField(
                    controller: evidenceController,
                    decoration: InputDecoration(
                        labelText: tr.text('evidence_optional'),
                        helperText: tr.text('evidence_optional_help'))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr.text('cancel'))),
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
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())));
                  }
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
  const _InventoryOverview(
      {required this.store,
      required this.products,
      required this.query,
      required this.searchController,
      required this.onScanBarcode,
      required this.onQuery,
      required this.onAdjust,
      required this.canAdjust});

  final AppStore store;
  final List<Product> products;
  final String query;
  final TextEditingController searchController;
  final VoidCallback onScanBarcode;
  final ValueChanged<String> onQuery;
  final ValueChanged<String>? onAdjust;
  final bool canAdjust;

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
                  SummaryCard(
                      title: tr.text('product_count'),
                      value: '${store.products.length}',
                      icon: Icons.inventory_2_outlined),
                  SummaryCard(
                      title: tr.text('total_units'),
                      value: '${store.totalUnitsInStock}',
                      icon: Icons.layers_outlined),
                  SummaryCard(
                      title: tr.text('low_stock_alerts'),
                      value: '${store.lowStockCount}',
                      icon: Icons.warning_amber_rounded),
                  SummaryCard(
                      title: tr.text('inventory_value'),
                      value: formatUsdReferenceAmount(
                          store.inventoryRetailValue, store.storeProfile),
                      icon: Icons.payments_outlined),
                  SummaryCard(
                      title: tr.text('pending_auto_corrections'),
                      value: '${store.pendingAutoCorrectionCount}',
                      icon: Icons.notifications_active_outlined),
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
                      title: Text(tr.text('inventory_overview'),
                          style: Theme.of(context).textTheme.titleMedium),
                      subtitle: Text(tr.text('inventory_page_desc')),
                    ),
                    const Divider(height: 1),
                    if (products.isEmpty)
                      Padding(
                          padding: VentioResponsive.pageInsets(context),
                          child: Text(tr.text('no_inventory_items'))),
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
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                          child: _InventoryProductTile(
                            product: product,
                            store: store,
                            compact: compact,
                            canAdjust: canAdjust,
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
  const _InventoryProductTile(
      {required this.product,
      required this.store,
      required this.compact,
      required this.onAdjust,
      required this.canAdjust});

  final Product product;
  final AppStore store;
  final bool compact;
  final ValueChanged<String>? onAdjust;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isLow =
        product.trackStock && product.stock <= product.lowStockThreshold;
    final meta = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(formatUsdReferenceAmount(product.price, store.storeProfile)),
        Chip(
            avatar: isLow ? const Icon(Icons.priority_high, size: 16) : null,
            label: Text('${tr.text('stock')}: ${product.stock}')),
        if (canAdjust)
          TextButton.icon(
              onPressed: onAdjust == null ? null : () => onAdjust!(product.id),
              icon: const Icon(Icons.tune),
              label: Text(tr.text('adjust'))),
      ],
    );
    if (compact) {
      return ListTile(
        leading: CircleAvatar(
            child: Icon(isLow
                ? Icons.warning_amber_rounded
                : Icons.inventory_2_outlined)),
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.code} • ${product.category}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            meta,
          ],
        ),
      );
    }
    return ListTile(
      leading: CircleAvatar(
          child: Icon(isLow
              ? Icons.warning_amber_rounded
              : Icons.inventory_2_outlined)),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.code} • ${product.category}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: VentioResponsive.clampToScreen(context, 360,
                min: 180, horizontalPadding: 120)),
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
        item.effectiveSaleUnits
            .any((unit) => unit.barcode.toLowerCase().contains(value)) ||
        item.effectivePurchaseUnits
            .any((unit) => unit.barcode.toLowerCase().contains(value));
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
            TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: tr.text('warehouse_name'))),
            const SizedBox(height: 12),
            TextField(
                controller: codeController,
                decoration:
                    InputDecoration(labelText: tr.text('code_optional'))),
            const SizedBox(height: 12),
            TextField(
                controller: locationController,
                decoration:
                    InputDecoration(labelText: tr.text('location_optional'))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                await widget.store.createWarehouse(
                    name: nameController.text,
                    code: codeController.text,
                    location: locationController.text);
                if (context.mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
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
    var toWarehouseId =
        warehouses.length > 1 ? warehouses[1].id : warehouses.first.id;
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
                items: products
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => productId = value ?? productId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: fromWarehouseId,
                decoration:
                    InputDecoration(labelText: tr.text('from_warehouse')),
                items: warehouses
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) => setDialogState(
                    () => fromWarehouseId = value ?? fromWarehouseId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: toWarehouseId,
                decoration: InputDecoration(labelText: tr.text('to_warehouse')),
                items: warehouses
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) => setDialogState(
                    () => toWarehouseId = value ?? toWarehouseId),
              ),
              const SizedBox(height: 12),
              Text(
                  '${tr.text('available')}: ${widget.store.stockForWarehouse(productId, fromWarehouseId)}'),
              const SizedBox(height: 12),
              TextField(
                  controller: qtyController,
                  decoration: InputDecoration(labelText: tr.text('quantity')),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: notesController,
                  decoration:
                      InputDecoration(labelText: tr.text('notes_optional'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.store.transferStock(
                      productId: productId,
                      fromWarehouseId: fromWarehouseId,
                      toWarehouseId: toWarehouseId,
                      quantity: double.tryParse(qtyController.text.trim()) ?? 0,
                      notes: notesController.text);
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) setState(() {});
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())));
                  }
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
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWarehousesManage,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Warehouses',
        message: 'Warehouse management is not available for your current role.',
      );
    }
    final warehouses = widget.store.warehouses;
    final products = widget.store.stockTrackedProducts;
    final stockRowsByWarehouse = <String, List<_WarehouseProductStock>>{
      for (final warehouse in warehouses)
        warehouse.id: <_WarehouseProductStock>[],
    };
    for (final product in products) {
      for (final entry
          in widget.store.warehouseStockForProduct(product.id).entries) {
        if (entry.value != 0) {
          (stockRowsByWarehouse[entry.key] ??= <_WarehouseProductStock>[]).add(
              _WarehouseProductStock(product: product, stock: entry.value));
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
              FilledButton.icon(
                  onPressed: _createWarehouse,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(tr.text('create_warehouse'))),
              OutlinedButton.icon(
                  onPressed: warehouses.length < 2 ? null : _transferStock,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(tr.text('transfer_stock'))),
            ]),
          );
        }
        final warehouse = warehouses[index - 1];
        final rows = stockRowsByWarehouse[warehouse.id] ??
            const <_WarehouseProductStock>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
            title: Text(warehouse.name),
            subtitle: Text([
              if (warehouse.code.isNotEmpty) warehouse.code,
              if (warehouse.location.isNotEmpty) warehouse.location
            ].join(' • ')),
            children: [
              for (final row in rows.take(100))
                ListTile(
                  dense: true,
                  title: Text(row.product.name),
                  trailing: Text('${row.stock}'),
                ),
              if (rows.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr.text('no_inventory_items'))),
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
    if (!store.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Stock movements',
        message: 'Stock movement history is not available for your current role.',
      );
    }
    final movements = store.stockMovements;
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Card(
          child: movements.isEmpty
              ? Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(tr.text('no_stock_movements')))
              : Column(
                  children: [
                    for (final movement in movements.take(200)) ...[
                      ListTile(
                        leading: CircleAvatar(
                            child: Icon(movement.quantity >= 0
                                ? Icons.add
                                : Icons.remove)),
                        title: Text(movement.productName),
                        subtitle: Text(
                            "${_movementTypeLabel(tr, movement.type)} • ${movement.warehouseName} • ${movement.referenceNo} • ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}${movement.notes.isNotEmpty ? ' • ${movement.notes}' : ''}${movement.evidenceRef.isNotEmpty ? ' • ${tr.text('evidence')}: ${movement.evidenceRef}' : ''}"),
                        isThreeLine: true,
                        trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  movement.quantity > 0
                                      ? '+${movement.quantity}'
                                      : '${movement.quantity}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (movement.unitCost > 0)
                                Text(formatUsdReferenceAmount(
                                    movement.value, store.storeProfile)),
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

class _AutoCorrectionsTab extends StatefulWidget {
  const _AutoCorrectionsTab({required this.store});

  final AppStore store;

  @override
  State<_AutoCorrectionsTab> createState() => _AutoCorrectionsTabState();
}

class _AutoCorrectionsTabState extends State<_AutoCorrectionsTab> {
  bool showReviewed = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canReview = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.productsEdit,
    });
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Auto corrections',
        message: 'Auto correction review is not available for your current role.',
      );
    }
    final allCorrections = widget.store.autoCorrectionMovements;
    final pending = widget.store.pendingAutoCorrectionMovements;
    final corrections = showReviewed ? allCorrections : pending;
    double totalQty = 0;
    double totalValue = 0;
    for (final item in corrections) {
      totalQty += item.quantity.abs();
      totalValue += item.value;
    }

    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('pending_auto_corrections'),
                value: '${pending.length}',
                icon: Icons.notifications_active_outlined),
            SummaryCard(
                title: tr.text('auto_corrections'),
                value: '${allCorrections.length}',
                icon: Icons.inventory_outlined),
            SummaryCard(
                title: tr.text('quantity'),
                value: totalQty.toStringAsFixed(
                    totalQty.truncateToDouble() == totalQty ? 0 : 2),
                icon: Icons.add_box_outlined),
            SummaryCard(
                title: tr.text('estimated_value'),
                value: formatUsdReferenceAmount(
                    totalValue, widget.store.storeProfile),
                icon: Icons.payments_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            value: showReviewed,
            onChanged: (value) => setState(() => showReviewed = value),
            title: Text(tr.text('show_reviewed_corrections')),
            subtitle: Text(tr.text('show_reviewed_corrections_desc')),
            secondary: const Icon(Icons.history_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: corrections.isEmpty
              ? Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(showReviewed
                      ? tr.text('no_auto_corrections')
                      : tr.text('no_pending_auto_corrections')),
                )
              : Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.fact_check_outlined)),
                      title: Text(tr.text('auto_corrections_need_review'),
                          style: Theme.of(context).textTheme.titleMedium),
                      subtitle:
                          Text(tr.text('auto_corrections_need_review_desc')),
                    ),
                    const Divider(height: 1),
                    for (final movement in corrections) ...[
                      ListTile(
                        leading: CircleAvatar(
                          child: Icon(movement.isReviewed
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded),
                        ),
                        title: Text(movement.productName),
                        subtitle: Text([
                          '${tr.text('quantity')}: +${movement.quantity}',
                          if (movement.referenceNo.isNotEmpty)
                            '${tr.text('invoice')}: ${movement.referenceNo}',
                          movement.date.toLocal().toString().split('.').first,
                          if (movement.deviceId.isNotEmpty)
                            '${tr.text('device')}: ${movement.deviceId}',
                          if (movement.reviewedBy.isNotEmpty)
                            '${tr.text('reviewed_by')}: ${movement.reviewedBy}',
                        ].join(' • ')),
                        isThreeLine: true,
                        trailing: movement.isReviewed
                            ? const Icon(Icons.done_all_outlined)
                            : canReview
                                ? FilledButton.icon(
                                    onPressed: () => _reviewMovement(movement.id),
                                    icon: const Icon(Icons.check),
                                    label: Text(tr.text('mark_reviewed')),
                                  )
                                : const Icon(Icons.lock_outline),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _reviewMovement(String id) async {
    final tr = AppLocalizations.of(context);
    try {
      await widget.store.reviewAutoCorrection(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr.text('auto_correction_marked_reviewed'))));
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _StockCountTab extends StatefulWidget {
  const _StockCountTab({required this.store});

  final AppStore store;

  @override
  State<_StockCountTab> createState() => _StockCountTabState();
}

class _StockCountTabState extends State<_StockCountTab> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCountsManage,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Stock count',
        message: 'Stock count actions are not available for your current role.',
      );
    }
    final sessions = widget.store.inventoryCountSessions;
    final active = widget.store.activeInventoryCountSession;
    final needle = query.trim().toLowerCase();
    final products = widget.store.stockTrackedProducts.where((product) {
      if (active == null || needle.isEmpty) return true;
      return product.name.toLowerCase().contains(needle) ||
          product.code.toLowerCase().contains(needle);
    }).toList();

    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('stock_count_sessions'),
                value: '${sessions.length}',
                icon: Icons.assignment_outlined),
            SummaryCard(
                title: tr.text('open_stock_count'),
                value: active == null ? '0' : '1',
                icon: Icons.pending_actions_outlined),
            if (active != null)
              SummaryCard(
                  title: tr.text('counted_products'),
                  value: '${active.countedLines}/${active.totalLines}',
                  icon: Icons.fact_check_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('stock_count'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(tr.text('stock_count_desc')),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: active == null ? _startCount : null,
                      icon: const Icon(Icons.add_task_outlined),
                      label: Text(tr.text('start_stock_count')),
                    ),
                    if (active != null) ...[
                      FilledButton.icon(
                        onPressed: active.countedLines == 0
                            ? null
                            : () => _approveCount(active.id),
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(tr.text('approve_stock_count')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _cancelCount(active.id),
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(tr.text('cancel')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (active != null) ...[
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: tr.text('search_products')),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_outlined)),
                  title: Text(
                      '${tr.text('active_stock_count')} • ${active.countNo}'),
                  subtitle: Text(
                      '${tr.text('started_at')}: ${active.createdAt.toLocal().toString().split('.').first}'),
                ),
                const Divider(height: 1),
                for (final product in products.take(200))
                  _StockCountProductTile(
                      store: widget.store,
                      sessionId: active.id,
                      product: product),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(tr.text('previous_stock_counts')),
              ),
              const Divider(height: 1),
              if (sessions.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr.text('no_stock_counts')))
              else
                for (final session in sessions.take(20))
                  ListTile(
                    leading: Icon(session.isApproved
                        ? Icons.verified_outlined
                        : session.isOpen
                            ? Icons.pending_actions_outlined
                            : Icons.cancel_outlined),
                    title: Text(session.countNo),
                    subtitle: Text(
                        '${tr.text('status')}: ${session.status} • ${tr.text('counted_products')}: ${session.countedLines}/${session.totalLines}'),
                    trailing: Text(session.createdAt
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startCount() async {
    try {
      await widget.store.createInventoryCountSession();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _approveCount(String id) async {
    try {
      await widget.store.approveInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _cancelCount(String id) async {
    try {
      await widget.store.cancelInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _StockCountProductTile extends StatelessWidget {
  const _StockCountProductTile(
      {required this.store, required this.sessionId, required this.product});

  final AppStore store;
  final String sessionId;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final session = store.activeInventoryCountSession;
    final matchingLines =
        session?.lines.where((item) => item.productId == product.id).toList() ??
            const [];
    final line = matchingLines.isEmpty ? null : matchingLines.first;
    final movementsAfter =
        line == null ? 0 : store.movementCountAfterInventoryLine(line);
    return ListTile(
      title: Text(product.name),
      subtitle: Text([
        '${tr.text('system_stock')}: ${product.stock}',
        if (line?.isCounted == true)
          '${tr.text('counted')}: ${line!.countedQty}',
        if (line?.countedAt != null)
          '${tr.text('counted_at')}: ${line!.countedAt!.toLocal().toString().split('.').first}',
        if (movementsAfter > 0)
          '⚠ ${tr.text('movements_after_count')}: $movementsAfter',
      ].join(' • ')),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: () => _enterCount(context),
        child: Text(
            line?.isCounted == true ? tr.text('recount') : tr.text('count')),
      ),
    );
  }

  Future<void> _enterCount(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr.text('count')} • ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: tr.text('actual_quantity')),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await store.countInventoryLine(
          sessionId: sessionId, productId: product.id, countedQty: value);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _WasteLossReport extends StatelessWidget {
  const _WasteLossReport({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!store.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Waste loss report',
        message: 'Waste and loss reporting is not available for your current role.',
      );
    }
    final lossMovements = store.stockMovements
        .where((item) =>
            item.type == 'inventory_loss' ||
            (item.type == 'inventory_adjustment' && item.quantity < 0))
        .toList();
    final totals = <String, _WasteTotal>{};
    double totalValue = 0;
    double totalQty = 0;
    for (final movement in lossMovements) {
      final key = movement.adjustmentCategory.isEmpty
          ? 'other'
          : movement.adjustmentCategory;
      final current = totals[key] ?? _WasteTotal();
      current.quantity += movement.quantity.abs();
      current.value += movement.value;
      current.count += 1;
      totals[key] = current;
      totalValue += movement.value;
      totalQty += movement.quantity.abs();
    }
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('loss_movements'),
                value: '${lossMovements.length}',
                icon: Icons.report_problem_outlined),
            SummaryCard(
                title: tr.text('loss_quantity'),
                value: totalQty.toStringAsFixed(
                    totalQty.truncateToDouble() == totalQty ? 0 : 2),
                icon: Icons.remove_circle_outline),
            SummaryCard(
                title: tr.text('loss_value'),
                value: formatUsdReferenceAmount(totalValue, store.storeProfile),
                icon: Icons.money_off_outlined),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: totals.isEmpty
              ? Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(tr.text('no_waste_loss_records')))
              : Column(
                  children: [
                    ListTile(
                        title: Text(tr.text('waste_loss_by_reason'),
                            style: Theme.of(context).textTheme.titleMedium)),
                    const Divider(height: 1),
                    for (final entry in totals.entries) ...[
                      ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.category_outlined)),
                        title: Text(_adjustmentCategoryLabel(tr, entry.key)),
                        subtitle: Text(
                            '${tr.text('movements')}: ${entry.value.count} • ${tr.text('quantity')}: ${entry.value.quantity}'),
                        trailing: Text(formatUsdReferenceAmount(
                            entry.value.value, store.storeProfile)),
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

class _InventoryAccessDenied extends StatelessWidget {
  const _InventoryAccessDenied({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
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

class _InventorySectionDenied extends StatelessWidget {
  const _InventorySectionDenied({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        _InventoryAccessDenied(title: title, message: message),
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
