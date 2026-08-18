import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/services/warehouse_transfer_pdf_service.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_transfer_order.dart';

class WarehouseTransferPage extends StatefulWidget {
  const WarehouseTransferPage({super.key, required this.store});

  final AppStore store;

  @override
  State<WarehouseTransferPage> createState() => _WarehouseTransferPageState();
}

class _WarehouseTransferPageState extends State<WarehouseTransferPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final List<_TransferDraftItem> _cart = <_TransferDraftItem>[];
  Map<String, double> _sourceBalances = <String, double>{};
  Future<List<WarehouseTransferOrder>>? _historyFuture;
  String _search = '';
  String _fromWarehouseId = '';
  String _toWarehouseId = '';
  bool _loadingStock = false;
  bool _saving = false;

  List<Warehouse> get _warehouses => widget.store.warehouses
      .where((warehouse) => !warehouse.isDeleted && warehouse.isActive)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final warehouses = _warehouses;
    if (warehouses.isNotEmpty) {
      _fromWarehouseId = warehouses.first.id;
      _toWarehouseId = warehouses.length > 1
          ? warehouses[1].id
          : warehouses.first.id;
    }
    _historyFuture = widget.store.recentWarehouseTransferOrders();
    _loadSourceBalances();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    for (final item in _cart) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSourceBalances() async {
    if (_fromWarehouseId.isEmpty) return;
    setState(() => _loadingStock = true);
    try {
      final all = await widget.store.warehouseStockBalancesFromSqlite();
      if (!mounted) return;
      setState(() {
        _sourceBalances = Map<String, double>.from(
          all[_fromWarehouseId] ?? const <String, double>{},
        );
      });
    } finally {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  List<Product> get _visibleProducts {
    final query = _search.trim().toLowerCase();
    final products = widget.store.stockTrackedProducts.where((product) {
      final available = _sourceBalances[product.id] ?? 0;
      if (available <= 0.0000001) return false;
      if (query.isEmpty) return true;
      final haystack = <String>[
        product.name,
        product.code,
        product.barcode,
        ...product.effectiveSaleUnits.map((unit) => unit.barcode),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
    products.sort((a, b) => a.name.compareTo(b.name));
    return products;
  }

  void _addProduct(Product product) {
    final existing = _cart.indexWhere((item) => item.product.id == product.id);
    if (existing >= 0) {
      final item = _cart[existing];
      final max = item.availableInSelectedUnit;
      final current = double.tryParse(item.quantityController.text) ?? 0;
      if (current + 1 <= max + 0.0000001) {
        item.quantityController.text = (current + 1).toStringAsFixed(
          (current + 1) % 1 == 0 ? 0 : 2,
        );
      }
      setState(() {
        if (existing > 0) {
          _cart
            ..removeAt(existing)
            ..insert(0, item);
        }
      });
      return;
    }
    final units = product.effectiveSaleUnits;
    final unit = units.first;
    final available = _sourceBalances[product.id] ?? 0;
    final initial = (available / unit.conversionToBase).clamp(0, 1).toDouble();
    final draft = _TransferDraftItem(
      product: product,
      availableBase: available,
      selectedUnitId: unit.id,
      quantity: initial > 0 ? initial : 0,
    );
    draft.quantityController.addListener(_onDraftChanged);
    setState(() => _cart.insert(0, draft));
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _removeItem(int index) {
    final item = _cart.removeAt(index);
    item.dispose();
    setState(() {});
  }

  String? _validateCart() {
    if (_fromWarehouseId == _toWarehouseId) {
      return 'Choose two different warehouses.';
    }
    if (_cart.isEmpty) return 'Add at least one product.';
    for (final item in _cart) {
      final qty = item.enteredQuantity;
      if (qty <= 0) return 'Enter a valid quantity for ${item.product.name}.';
      if (item.baseQuantity > item.availableBase + 0.0000001) {
        return 'Insufficient stock for ${item.product.name}.';
      }
    }
    return null;
  }

  Future<void> _submitTransfer() async {
    final error = _validateCart();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      final order = await widget.store.createWarehouseTransferOrder(
        fromWarehouseId: _fromWarehouseId,
        toWarehouseId: _toWarehouseId,
        notes: _notesController.text.trim(),
        items: _cart.map((draft) {
          final unit = draft.selectedUnit;
          return WarehouseTransferOrderItem(
            productId: draft.product.id,
            productName: draft.product.name,
            quantity: draft.enteredQuantity,
            unitId: unit.id,
            unitName: unit.name,
            conversionToBase: unit.conversionToBase,
          );
        }).toList(growable: false),
      );
      if (!mounted) return;
      for (final item in _cart) {
        item.dispose();
      }
      _cart.clear();
      _notesController.clear();
      _historyFuture = widget.store.recentWarehouseTransferOrders();
      await _loadSourceBalances();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer order ${order.orderNo} completed.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizedErrorText(AppLocalizations.of(context), error)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final warehouses = _warehouses;
    if (warehouses.length < 2) {
      return Scaffold(
        appBar: AppBar(title: Text(tr.text('transfer_stock'))),
        body: const Center(child: Text('Create at least two warehouses first.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('transfer_stock')),
        actions: [
          IconButton(
            tooltip: tr.text('refresh_stock'),
            onPressed: _loadingStock ? null : _loadSourceBalances,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWarehouseHeader(warehouses),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 950) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: _buildProductPane()),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 5, child: _buildCartPane()),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 5, child: _buildProductPane()),
                    const Divider(height: 1),
                    Expanded(flex: 6, child: _buildCartPane()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseHeader(List<Warehouse> warehouses) {
    final tr = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              key: ValueKey('from-warehouse-$_fromWarehouseId'),
              initialValue: _fromWarehouseId,
              decoration: InputDecoration(
                labelText: tr.text('from_warehouse'),
                prefixIcon: const Icon(Icons.warehouse_outlined),
              ),
              items: warehouses
                  .map((warehouse) => DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(warehouse.name),
                      ))
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) async {
                      if (value == null || value == _fromWarehouseId) return;
                      setState(() {
                        _fromWarehouseId = value;
                        if (_toWarehouseId == value) {
                          _toWarehouseId = warehouses
                              .firstWhere((item) => item.id != value)
                              .id;
                        }
                        for (final item in _cart) {
                          item.dispose();
                        }
                        _cart.clear();
                      });
                      await _loadSourceBalances();
                    },
            ),
          ),
          const Icon(Icons.arrow_forward_rounded),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              key: ValueKey('to-warehouse-$_toWarehouseId'),
              initialValue: _toWarehouseId,
              decoration: InputDecoration(
                labelText: tr.text('to_warehouse'),
                prefixIcon: const Icon(Icons.inventory_2_outlined),
              ),
              items: warehouses
                  .where((warehouse) => warehouse.id != _fromWarehouseId)
                  .map((warehouse) => DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(warehouse.name),
                      ))
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _toWarehouseId = value);
                    },
            ),
          ),
          if (_loadingStock)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildProductPane() {
    final products = _visibleProducts;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).text('search_products_barcode'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
            onSubmitted: (_) {
              if (products.length == 1) {
                _addProduct(products.first);
                _searchController.clear();
                setState(() => _search = '');
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingStock
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? Center(
                        child: Text(AppLocalizations.of(context).text('no_stock_in_warehouse')),
                      )
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final available = _sourceBalances[product.id] ?? 0;
                          return ListTile(
                            title: Text(product.name),
                            subtitle: Text(
                              '${product.code.isEmpty ? product.barcode : product.code}  •  Available: ${_fmt(available)} ${product.unit}',
                            ),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => _addProduct(product),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined),
              const SizedBox(width: 8),
              Text(
                '${AppLocalizations.of(context).text('warehouse_transfer_order')} (${_cart.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text('${AppLocalizations.of(context).text('total')}: ${_fmt(_cart.fold<double>(0, (s, i) => s + i.baseQuantity))}'),
            ],
          ),
        ),
        Expanded(
          child: _cart.isEmpty
              ? Center(
                  child: Text(AppLocalizations.of(context).text('select_products_for_transfer')),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _buildCartRow(index),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).text('transfer_notes_optional'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submitTransfer,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(AppLocalizations.of(context).text('complete_transfer_order')),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(AppLocalizations.of(context).text('recent_transfer_orders')),
                children: [_buildHistory()],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartRow(int index) {
    final item = _cart[index];
    final units = item.product.effectiveSaleUnits;
    final overStock = item.baseQuantity > item.availableBase + 0.0000001;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  'Available: ${_fmt(item.availableInSelectedUnit)} ${item.selectedUnit.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<String>(
              key: ValueKey('${item.product.id}:${item.selectedUnitId}'),
              initialValue: item.selectedUnitId,
              isDense: true,
              items: units
                  .map((unit) => DropdownMenuItem(
                        value: unit.id,
                        child: Text(unit.name),
                      ))
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() => item.selectedUnitId = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: item.quantityController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Qty',
                errorText: overStock ? 'Max ${_fmt(item.availableInSelectedUnit)}' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).text('remove'),
            onPressed: () => _removeItem(index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    final future = _historyFuture;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<WarehouseTransferOrder>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          );
        }
        final orders = snapshot.data ?? const <WarehouseTransferOrder>[];
        if (orders.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(AppLocalizations.of(context).text('no_transfer_orders')),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: orders.take(20).length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.swap_horiz),
                title: Text(order.orderNo),
                subtitle: Text(
                  '${order.fromWarehouseName} → ${order.toWarehouseName} • ${order.items.length} products • ${_fmt(order.totalUnits)} units',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_dateText(order.date)),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: Localizations.localeOf(context).languageCode == 'ar'
                          ? 'طباعة'
                          : 'Print',
                      onPressed: () => _printOrder(order),
                      icon: const Icon(Icons.print_outlined),
                    ),
                  ],
                ),
                onTap: () => _showOrderDetails(order),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _printOrder(WarehouseTransferOrder order) async {
    try {
      await WarehouseTransferPdfService.printTransferOrder(
        order: order,
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

  Future<void> _showOrderDetails(WarehouseTransferOrder order) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(order.orderNo),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${order.fromWarehouseName} → ${order.toWarehouseName}'),
              Text(_dateText(order.date)),
              if (order.notes.isNotEmpty) Text(order.notes),
              const Divider(),
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.productName),
                      trailing: Text(
                        '${_fmt(item.quantity)} ${item.unitName} (${_fmt(item.baseQuantity)} base)',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).text('close')),
          ),
        ],
      ),
    );
  }

  static String _fmt(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _TransferDraftItem {
  _TransferDraftItem({
    required this.product,
    required this.availableBase,
    required this.selectedUnitId,
    required double quantity,
  }) : quantityController = TextEditingController(
          text: quantity % 1 == 0
              ? quantity.toStringAsFixed(0)
              : quantity.toStringAsFixed(2),
        );

  final Product product;
  final double availableBase;
  String selectedUnitId;
  final TextEditingController quantityController;

  ProductSaleUnit get selectedUnit => product.effectiveSaleUnits.firstWhere(
        (unit) => unit.id == selectedUnitId,
        orElse: () => product.effectiveSaleUnits.first,
      );

  double get enteredQuantity =>
      double.tryParse(quantityController.text.trim()) ?? 0;
  double get baseQuantity => enteredQuantity * selectedUnit.conversionToBase;
  double get availableInSelectedUnit => selectedUnit.conversionToBase <= 0
      ? 0
      : availableBase / selectedUnit.conversionToBase;

  void dispose() => quantityController.dispose();
}
