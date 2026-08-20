import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/supplier.dart';
import '../../models/warehouse.dart';

/// Purchase workbench deliberately mirrors the Sales page: products on one
/// side, the live document/cart on the other.  It replaces the former
/// list-first Purchases screen; the old screen remains in the codebase only as
/// a legacy implementation while this widget is the routed Purchases page.
class PurchaseWorkstationPage extends StatefulWidget {
  const PurchaseWorkstationPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PurchaseWorkstationPage> createState() =>
      _PurchaseWorkstationPageState();
}

class _PurchaseWorkstationPageState extends State<PurchaseWorkstationPage> {
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _shortcutFocusNode = FocusNode(debugLabel: 'purchase_workstation');
  final List<_DraftPurchaseLine> _cart = [];
  late Future<void> _dataFuture;
  String _search = '';
  String _supplierId = '';
  String _warehouseId = Warehouse.defaultId;
  final String _paymentMethod = 'Cash';
  String _paymentStatus = 'paid';
  bool _receiveNow = true;
  bool _saving = false;
  Purchase? _editingPurchase;

  @override
  void initState() {
    super.initState();
    _dataFuture = widget.store.ensurePurchasesPageDataLoaded();
    widget.store.addListener(_onStoreChanged);
    HardwareKeyboard.instance.addHandler(_handleShortcut);
  }

  @override
  void didUpdateWidget(covariant PurchaseWorkstationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
      _dataFuture = widget.store.ensurePurchasesPageDataLoaded();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    _searchController.dispose();
    _barcodeController.dispose();
    _searchFocusNode.dispose();
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  bool _handleShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _searchFocusNode.requestFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f9) {
      _savePurchase();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _cart.isNotEmpty) {
      _confirmClearCart();
      return true;
    }
    return false;
  }

  List<Product> get _products => widget.store.products
          .where((item) => item.isActive && item.trackStock)
          .where((item) {
        final query = _search.trim().toLowerCase();
        if (query.isEmpty) return true;
        return '${item.name} ${item.nameEn} ${item.nameAr} ${item.code} ${item.barcode} ${item.brand} ${item.supplier}'
            .toLowerCase()
            .contains(query);
      }).toList();

  Supplier? get _supplier {
    for (final supplier in widget.store.suppliers) {
      if (supplier.id == _supplierId) return supplier;
    }
    return null;
  }

  Warehouse get _warehouse => widget.store.resolveWarehouseForPurchase(
        warehouseId: _warehouseId,
      );

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.total);

  String _amount(double value) => formatUsdReferenceAmount(
        value,
        widget.store.storeProfile,
      );

  Future<void> _addProduct(Product product) async {
    final unit = product.effectivePurchaseUnits.first;
    final supplierPrice = _supplierId.isEmpty
        ? null
        : widget.store.supplierProductPriceFor(
            productId: product.id, supplierId: _supplierId);
    final remembered = _supplierId.isEmpty
        ? widget.store.lastPurchasePriceForProduct(product.id)
        : widget.store.lastPurchasePriceFor(
            productId: product.id, supplierId: _supplierId);
    final defaultCost = supplierPrice == null
        ? (remembered ?? product.usdCost) * unit.conversionToBase
        : toUsdReferencePrice(supplierPrice.cost, supplierPrice.currency,
                widget.store.storeProfile) *
            unit.conversionToBase;
    final quantity = TextEditingController(text: '1');
    final cost = TextEditingController(text: defaultCost.toStringAsFixed(2));
    final result = await showDialog<_DraftPurchaseLine>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: SizedBox(
          width: 390,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${unit.name} • ${_amount(defaultCost)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).text('quantity')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).text('cost')),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(quantity.text.trim()) ?? 0;
              final enteredCost = double.tryParse(cost.text.trim()) ?? -1;
              if (qty <= 0 || enteredCost < 0) return;
              Navigator.pop(
                  context,
                  _DraftPurchaseLine(
                      product: product,
                      unit: unit,
                      quantity: qty,
                      unitCost: enteredCost));
            },
            child: Text(AppLocalizations.of(context).text('add_to_cart')),
          ),
        ],
      ),
    );
    quantity.dispose();
    cost.dispose();
    if (result == null || !mounted) return;
    setState(() {
      final existing = _cart.indexWhere((line) =>
          line.product.id == result.product.id &&
          line.unit.id == result.unit.id &&
          line.unitCost == result.unitCost);
      if (existing >= 0) {
        _cart[existing] = _cart[existing]
            .copyWith(quantity: _cart[existing].quantity + result.quantity);
      } else {
        _cart.add(result);
      }
    });
  }

  Future<void> _addBarcode() async {
    final code = _barcodeController.text.trim();
    if (code.isEmpty) return;
    _barcodeController.clear();
    for (final product in widget.store.products) {
      if (product.code == code ||
          product.barcode == code ||
          product.purchaseUnitForBarcode(code) != null) {
        await _addProduct(product);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('barcode_not_registered_purchase'))));
    }
  }

  Future<void> _confirmClearCart() async {
    if (_cart.isEmpty) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context).text('clear_cart')),
              content:
                  Text(AppLocalizations.of(context).text('confirm_clear_cart')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(AppLocalizations.of(context).text('cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child:
                        Text(AppLocalizations.of(context).text('clear_cart')))
              ],
            ));
    if (accepted == true && mounted) setState(_cart.clear);
  }

  Future<void> _savePurchase() async {
    final tr = AppLocalizations.of(context);
    if (_saving || _cart.isEmpty) return;
    final supplier = _supplier;
    if (supplier == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.text('supplier_required'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final items =
          _cart.map((line) => line.toPurchaseItem(widget.store)).toList();
      final editing = _editingPurchase;
      if (editing == null) {
        await widget.store.createPurchase(
          supplierId: supplier.id,
          supplierName: supplier.name,
          items: items,
          receiveNow: _receiveNow,
          paymentMethod: _paymentMethod,
          paymentStatus: _paymentStatus,
          warehouseId: _warehouse.id,
          warehouseName: _warehouse.name,
        );
      } else if (editing.isReceived) {
        throw StateError('Received purchase invoices cannot be edited.');
      } else {
        await widget.store.updatePurchaseDraft(
          id: editing.id,
          supplierId: supplier.id,
          supplierName: supplier.name,
          items: items,
          paymentMethod: _paymentMethod,
          paymentStatus: _paymentStatus,
          warehouseId: _warehouse.id,
          warehouseName: _warehouse.name,
          note: editing.note,
        );
      }
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _editingPurchase = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(editing == null
              ? tr.text('purchase_saved')
              : tr.text('purchase_updated'))));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showPurchaseHistory() async {
    final tr = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
              child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .78,
                  child: Column(children: [
                    ListTile(
                        title: Text(tr.text('purchase_invoice'),
                            style: Theme.of(context).textTheme.titleLarge),
                        trailing: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close))),
                    Expanded(
                        child: ListView.separated(
                      itemCount: widget.store.purchases.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final purchase = widget.store.purchases[index];
                        return ListTile(
                          leading: Icon(purchase.isReceived
                              ? Icons.inventory_2_outlined
                              : Icons.edit_note_outlined),
                          title: Text(
                              '${purchase.purchaseNo} · ${purchase.supplierName}'),
                          subtitle: Text(
                              '${purchase.status} · ${purchase.items.length} ${tr.text('items')}'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_amount(purchase.subtotal)),
                          ]),
                        );
                      },
                    )),
                  ])),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canManagePurchases) {
      return Scaffold(
          body: Center(child: Text(tr.text('no_access_purchase_records'))));
    }
    return PageTimingScope(
      pageKey: 'purchases_workstation',
      child: FutureBuilder<void>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return Focus(
            focusNode: _shortcutFocusNode,
            autofocus: true,
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = VentioResponsive.isMobile(context) ||
                  constraints.maxWidth < 900;
              final cart = _buildCart(context, tr);
              final products = _buildProducts(context, tr);
              return Scaffold(
                appBar: AppBar(title: Text(tr.text('purchases')), actions: [
                  IconButton(
                      tooltip: tr.text('purchase_invoice'),
                      onPressed: _showPurchaseHistory,
                      icon: const Icon(Icons.receipt_long_outlined)),
                  IconButton(
                      tooltip: tr.text('clear_cart'),
                      onPressed: _confirmClearCart,
                      icon: const Icon(Icons.delete_sweep_outlined)),
                ]),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: compact
                      ? Column(children: [
                          Expanded(child: products),
                          const SizedBox(height: 12),
                          SizedBox(height: 350, child: cart)
                        ])
                      : Row(children: [
                          Expanded(flex: 5, child: cart),
                          const SizedBox(width: 16),
                          Expanded(flex: 6, child: products)
                        ]),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildProducts(BuildContext context, AppLocalizations tr) => Card(
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr.text('products'),
                  style: Theme.of(context).textTheme.titleLarge)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr.text('search_products_pro')))),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                  controller: _barcodeController,
                  onSubmitted: (_) => _addBarcode(),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      hintText: tr.text('scan_purchase_barcode_hint'),
                      suffixIcon: IconButton(
                          onPressed: _addBarcode,
                          icon: const Icon(Icons.add_circle_outline))))),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10),
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                return InkWell(
                  onTap: () => _addProduct(product),
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.inventory_2_outlined),
                            const Spacer(),
                            Text(product.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                                '${tr.text('cost')}: ${_amount(product.usdCost)}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      );

  Widget _buildCart(BuildContext context, AppLocalizations tr) => Card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  _editingPurchase == null
                      ? tr.text('purchase_invoice')
                      : '${tr.text('edit')} · ${_editingPurchase!.purchaseNo}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_editingPurchase != null)
                IconButton(
                  tooltip: tr.text('cancel'),
                  onPressed: () => setState(() {
                    _editingPurchase = null;
                    _cart.clear();
                  }),
                  icon: const Icon(Icons.close),
                ),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                  initialValue: _supplierId.isEmpty ? null : _supplierId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr.text('supplier')),
                  items: widget.store.suppliers
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _supplierId = v ?? ''))),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DropdownButtonFormField<String>(
                  initialValue: _warehouse.id,
                  decoration: InputDecoration(labelText: tr.text('warehouse')),
                  items: widget.store.warehouses
                      .map((w) =>
                          DropdownMenuItem(value: w.id, child: Text(w.name)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _warehouseId = v ?? Warehouse.defaultId))),
          Expanded(
              child: _cart.isEmpty
                  ? Center(child: Text(tr.text('shortcut_cart_empty')))
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final line = _cart[index];
                        return ListTile(
                          title: Text(line.product.name),
                          subtitle: Text(
                              '${line.quantity} ${line.unit.name} × ${_amount(line.unitCost)}'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_amount(line.total)),
                            IconButton(
                                onPressed: () =>
                                    setState(() => _cart.removeAt(index)),
                                icon: const Icon(Icons.close))
                          ]),
                          onTap: () => _addProduct(line.product),
                        );
                      })),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr.text('purchase_total'),
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(_amount(_subtotal),
                          style: Theme.of(context).textTheme.titleLarge)
                    ]),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _receiveNow,
                    onChanged: (v) => setState(() => _receiveNow = v),
                    title: Text(tr.text('receive_now')),
                    subtitle: Text(tr.text('receive_now_desc'))),
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'paid', label: Text('Paid')),
                      ButtonSegment(value: 'credit', label: Text('Credit'))
                    ],
                    selected: {
                      _paymentStatus
                    },
                    onSelectionChanged: (v) =>
                        setState(() => _paymentStatus = v.first)),
                const SizedBox(height: 10),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: _saving ? null : _savePurchase,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(_editingPurchase != null
                            ? tr.text('purchase_updated')
                            : (_receiveNow
                                ? tr.text('purchase_saved')
                                : tr.text('draft'))))),
              ])),
        ]),
      );
}

class _DraftPurchaseLine {
  const _DraftPurchaseLine(
      {required this.product,
      required this.unit,
      required this.quantity,
      required this.unitCost});
  final Product product;
  final ProductSaleUnit unit;
  final double quantity;
  final double unitCost;
  double get total => quantity * unitCost;
  _DraftPurchaseLine copyWith({double? quantity}) => _DraftPurchaseLine(
      product: product,
      unit: unit,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost);
  PurchaseItem toPurchaseItem(AppStore store) => PurchaseItem(
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitCost: unitCost,
      purchaseUnitId: unit.id,
      purchaseUnitName: unit.name,
      conversionToBase: unit.conversionToBase,
      originalUnitCost: unitCost,
      unitCostCurrency: 'USD',
      exchangeRateAtEntry: store.storeProfile.usdToLbpRate);
}
