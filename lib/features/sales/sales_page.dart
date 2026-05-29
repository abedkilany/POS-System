import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';


enum _BarcodeAddResult {
  added,
  empty,
  notAllowed,
  notFound,
  outOfStock,
  stockLimitReached,
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  static const String _quickPagesStorageKey = 'sale_quick_product_pages_v1';

  final List<_DraftSaleItem> _cart = [];
  final List<_QuickProductPage> _quickPages = [];
  String _selectedCustomerId = AppStore.walkInCustomerId;
  String _paymentMethod = 'Cash';
  String _search = '';
  List<_DraftSaleItem>? _heldCart;
  final MobileScannerController _scannerController = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _scannerActive = false;
  bool _manualBarcodeInput = false;
  bool _quickGridEditMode = false;
  int _selectedQuickPageIndex = 0;
  String? _lastScannedCode;
  DateTime? _lastScannedAt;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = AppStore.walkInCustomerId;
    _loadQuickProductPages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _manualBarcodeInput) return;
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _discountController.dispose();
    _barcodeFocusNode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  double get _discount {
    final value = double.tryParse(_discountController.text) ?? 0;
    return value < 0 ? 0 : value;
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);
  double get _total => (_subtotal - _discount).clamp(0, double.infinity).toDouble();
  int get _itemsCount => _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final sales = widget.store.sales;
    final products = widget.store.products.where((product) => product.stock > 0).where((product) {
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return product.name.toLowerCase().contains(q) || product.code.toLowerCase().contains(q) || product.category.toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        final pagePadding = VentioResponsive.pagePadding(context);

        if (!isWide) {
          return _buildMobileSalesLayout(context, tr, products, pagePadding);
        }

        return _buildDesktopSalesLayout(context, tr, products, sales, pagePadding);
      },
    );
  }


  Widget _buildDesktopSalesLayout(BuildContext context, AppLocalizations tr, List<Product> products, List<Sale> sales, double pagePadding) {
    return Padding(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('pos_terminal'),
            subtitle: tr.text('pos_terminal_desc'),
            action: OutlinedButton.icon(
              onPressed: _showInvoicesSheet,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(tr.text('recent_invoices')),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 6, child: _buildCurrentSalePanel(context, tr, products)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _buildQuickProductGridPanel(context, tr, products)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildDesktopInvoiceSummaryBar(context, tr),
        ],
      ),
    );
  }

  Widget _buildCurrentSalePanel(BuildContext context, AppLocalizations tr, List<Product> products) {
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBarcodeStation(context, tr, products: products),
            const SizedBox(height: 12),
            Expanded(child: _buildCart(context, tr, showTotals: false, showActions: false)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopInvoiceSummaryBar(BuildContext context, AppLocalizations tr) {
    final customerName = widget.store.resolveCustomerName(_selectedCustomerId);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: widget.store.sanitizeSelectedCustomerId(_selectedCustomerId),
                items: widget.store.customers.map((customer) => DropdownMenuItem<String>(value: customer.id, child: Text(customer.name))).toList(),
                decoration: InputDecoration(labelText: tr.text('customer'), isDense: true),
                onChanged: (value) => setState(() => _selectedCustomerId = widget.store.sanitizeSelectedCustomerId(value)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _discountController,
                decoration: InputDecoration(labelText: tr.text('discount'), isDense: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: InputDecoration(labelText: tr.text('payment'), isDense: true),
                items: [
                  DropdownMenuItem(value: 'Cash', child: Text(tr.text('payment_cash'))),
                  DropdownMenuItem(value: 'Card', child: Text(tr.text('payment_card'))),
                  DropdownMenuItem(value: 'Transfer', child: Text(tr.text('payment_transfer'))),
                  DropdownMenuItem(value: 'Mixed', child: Text(tr.text('payment_mixed'))),
                ],
                onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$customerName • ${_paymentMethodLabel(tr, _paymentMethod)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text('$_itemsCount ${tr.text('items_count')} | ${formatUsdReferenceAmount(_total, widget.store.storeProfile)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: true),
              icon: const Icon(Icons.point_of_sale),
              label: Text(tr.text('complete_sale_print')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: false),
              icon: const Icon(Icons.save_outlined),
              label: Text(tr.text('save_only')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickProductGridPanel(BuildContext context, AppLocalizations tr, List<Product> products) {
    _ensureQuickPages(products, tr);
    final page = _quickPages[_selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt()];
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr.text('quick_product_grid'), style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(
                  onPressed: () => setState(() => _quickGridEditMode = !_quickGridEditMode),
                  icon: Icon(_quickGridEditMode ? Icons.check : Icons.edit_outlined),
                  label: Text(_quickGridEditMode ? tr.text('save') : tr.text('edit_layout')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  Expanded(
                    child: _quickGridEditMode
                        ? ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            buildDefaultDragHandles: false,
                            itemCount: _quickPages.length,
                            onReorder: _moveQuickPage,
                            proxyDecorator: (child, _, __) => Material(elevation: 6, borderRadius: BorderRadius.circular(24), child: child),
                            itemBuilder: (context, index) {
                              final selected = index == _selectedQuickPageIndex;
                              return Padding(
                                key: ValueKey('quick_page_${index}_${_quickPages[index].name}'),
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: ReorderableDragStartListener(
                                  index: index,
                                  child: InputChip(
                                    avatar: const Icon(Icons.drag_indicator, size: 18),
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: Text(_quickPages[index].name, overflow: TextOverflow.ellipsis)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit_outlined, size: 16),
                                      ],
                                    ),
                                    selected: selected,
                                    onSelected: (_) {
                                      if (selected) {
                                        _renameQuickPage(index);
                                      } else {
                                        setState(() => _selectedQuickPageIndex = index);
                                      }
                                    },
                                    deleteIcon: _quickPages.length > 1 ? const Icon(Icons.close, size: 18) : null,
                                    onDeleted: _quickPages.length > 1 ? () => _deleteQuickPage(index) : null,
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _quickPages.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final selected = index == _selectedQuickPageIndex;
                              return InputChip(
                                label: Text(_quickPages[index].name),
                                selected: selected,
                                onSelected: (_) => setState(() => _selectedQuickPageIndex = index),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(tr.text('page')),
                    onPressed: _addQuickPage,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 520 ? 3 : 2;
                  return GridView.builder(
                    itemCount: page.slots.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.18,
                    ),
                    itemBuilder: (context, index) {
                      final slot = page.slots[index];
                      final product = slot.productId == null ? null : _productById(slot.productId!);
                      final isEmpty = product == null;
                      final child = _buildQuickProductTile(context, tr, page, index, slot, product, isEmpty);
                      if (!_quickGridEditMode) return child;
                      final target = DragTarget<int>(
                        onWillAcceptWithDetails: (details) => details.data != index,
                        onAcceptWithDetails: (details) => _moveQuickSlot(details.data, index),
                        builder: (_, candidateData, ___) {
                          if (candidateData.isEmpty) return child;
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                            ),
                            child: child,
                          );
                        },
                      );
                      if (isEmpty) return target;
                      return LongPressDraggable<int>(
                        data: index,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(width: 150, height: 120, child: child),
                        ),
                        childWhenDragging: Opacity(opacity: 0.35, child: child),
                        child: target,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickProductTile(BuildContext context, AppLocalizations tr, _QuickProductPage page, int index, _QuickProductSlot slot, Product? product, bool isEmpty) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (isEmpty || _quickGridEditMode) {
          _configureQuickSlot(page, index);
        } else {
          _addProduct(product!);
        }
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isEmpty ? scheme.surfaceContainerHighest.withValues(alpha: 0.35) : scheme.primaryContainer.withValues(alpha: 0.40),
          border: Border.all(color: isEmpty ? scheme.outlineVariant : scheme.primary.withValues(alpha: 0.28)),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: isEmpty
                    ? Icon(Icons.add, size: 34, color: scheme.primary)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(slot.shortName?.trim().isNotEmpty == true ? slot.shortName!.trim() : product!.name, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(formatUsdReferenceAmount(product!.price, widget.store.storeProfile), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
              ),
            ),
            if (_quickGridEditMode && !isEmpty)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: tr.text('delete'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _clearQuickSlot(page, index),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            if (_quickGridEditMode && !isEmpty)
              const Positioned(left: 8, bottom: 8, child: Icon(Icons.drag_indicator, size: 20)),
          ],
        ),
      ),
    );
  }


  void _loadQuickProductPages() {
    final raw = LocalDatabaseService.getString(_quickPagesStorageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _quickPages
        ..clear()
        ..addAll(decoded.whereType<Map<String, dynamic>>().map(_QuickProductPage.fromJson));
    } catch (_) {
      _quickPages.clear();
    }
  }

  void _ensureQuickPages(List<Product> products, AppLocalizations tr) {
    if (_quickPages.isEmpty) {
      _quickPages.add(
        _QuickProductPage(
          name: tr.text('favorites'),
          slots: List.generate(12, (index) {
            if (index < products.length && index < 6) {
              final product = products[index];
              return _QuickProductSlot(productId: product.id, shortName: _shortProductName(product.name));
            }
            return const _QuickProductSlot();
          }),
        ),
      );
      unawaited(_saveQuickProductPages());
    }
    if (_selectedQuickPageIndex >= _quickPages.length) _selectedQuickPageIndex = _quickPages.length - 1;
    if (_selectedQuickPageIndex < 0) _selectedQuickPageIndex = 0;
  }

  Future<void> _saveQuickProductPages() => LocalDatabaseService.setString(
        _quickPagesStorageKey,
        jsonEncode(_quickPages.map((page) => page.toJson()).toList()),
      );

  String _shortProductName(String name) {
    final clean = name.trim();
    if (clean.length <= 14) return clean;
    return clean.substring(0, 14).trim();
  }

  Product? _productById(String id) {
    for (final product in widget.store.products) {
      if (product.id == id && product.stock > 0) return product;
    }
    return null;
  }

  void _addQuickPage() {
    setState(() {
      _quickPages.add(_QuickProductPage(name: '${AppLocalizations.of(context).text('page')} ${_quickPages.length + 1}', slots: List.generate(12, (_) => const _QuickProductSlot())));
      _selectedQuickPageIndex = _quickPages.length - 1;
      _quickGridEditMode = true;
    });
    unawaited(_saveQuickProductPages());
  }

  void _deleteQuickPage(int index) {
    if (_quickPages.length <= 1 || index < 0 || index >= _quickPages.length) return;
    setState(() {
      _quickPages.removeAt(index);
      _selectedQuickPageIndex = _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    });
    unawaited(_saveQuickProductPages());
  }

  Future<void> _renameQuickPage(int index) async {
    if (index < 0 || index >= _quickPages.length) return;
    final controller = TextEditingController(text: _quickPages[index].name);
    final tr = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('rename_quick_page')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: tr.text('page_name')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(tr.text('save'))),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    setState(() => _quickPages[index].name = result.trim());
    unawaited(_saveQuickProductPages());
  }

  void _moveQuickPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _quickPages.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= _quickPages.length || oldIndex == newIndex) return;
    setState(() {
      final page = _quickPages.removeAt(oldIndex);
      _quickPages.insert(newIndex, page);
      if (_selectedQuickPageIndex == oldIndex) {
        _selectedQuickPageIndex = newIndex;
      } else if (oldIndex < _selectedQuickPageIndex && newIndex >= _selectedQuickPageIndex) {
        _selectedQuickPageIndex -= 1;
      } else if (oldIndex > _selectedQuickPageIndex && newIndex <= _selectedQuickPageIndex) {
        _selectedQuickPageIndex += 1;
      }
    });
    unawaited(_saveQuickProductPages());
  }

  void _moveQuickSlot(int fromIndex, int toIndex) {
    if (_selectedQuickPageIndex < 0 || _selectedQuickPageIndex >= _quickPages.length) return;
    final page = _quickPages[_selectedQuickPageIndex];
    if (fromIndex < 0 || fromIndex >= page.slots.length || toIndex < 0 || toIndex >= page.slots.length || fromIndex == toIndex) return;
    setState(() {
      final moved = page.slots.removeAt(fromIndex);
      page.slots.insert(toIndex, moved);
    });
    unawaited(_saveQuickProductPages());
  }

  void _clearQuickSlot(_QuickProductPage page, int index) {
    if (index < 0 || index >= page.slots.length) return;
    setState(() => page.slots[index] = const _QuickProductSlot());
    unawaited(_saveQuickProductPages());
  }

  Future<void> _configureQuickSlot(_QuickProductPage page, int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= page.slots.length) return;
    final tr = AppLocalizations.of(context);
    final products = widget.store.products.where((product) => product.stock > 0).toList();
    final nameController = TextEditingController(text: page.slots[slotIndex].shortName ?? '');
    Product? selected = page.slots[slotIndex].productId == null ? null : _productById(page.slots[slotIndex].productId!);
    var query = '';
    final result = await showDialog<_QuickProductSlot>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = products.where((product) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return product.name.toLowerCase().contains(q) || product.code.toLowerCase().contains(q) || product.category.toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: Text(tr.text('quick_product_shortcut')),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: tr.text('search_product')),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: tr.text('short_name')),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text(tr.text('no_products')))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              final isSelected = selected?.id == product.id;
                              return ListTile(
                                selected: isSelected,
                                leading: Icon(isSelected ? Icons.check_circle : Icons.inventory_2_outlined),
                                title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${product.code} • ${tr.text('stock')}: ${product.stock}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Text(formatUsdReferenceAmount(product.price, widget.store.storeProfile)),
                                onTap: () {
                                  setDialogState(() {
                                    selected = product;
                                    if (nameController.text.trim().isEmpty) nameController.text = _shortProductName(product.name);
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
              if (page.slots[slotIndex].productId != null)
                TextButton(onPressed: () => Navigator.pop(dialogContext, const _QuickProductSlot()), child: Text(tr.text('delete'))),
              FilledButton(
                onPressed: selected == null ? null : () => Navigator.pop(dialogContext, _QuickProductSlot(productId: selected!.id, shortName: nameController.text.trim().isEmpty ? _shortProductName(selected!.name) : nameController.text.trim())),
                child: Text(tr.text('save')),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    if (result == null) return;
    setState(() => page.slots[slotIndex] = result);
    unawaited(_saveQuickProductPages());
  }

  Widget _buildMobileSalesLayout(BuildContext context, AppLocalizations tr, List<Product> products, double pagePadding) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(pagePadding),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMobileSaleControls(context, tr, products),
            const SizedBox(height: 8),
            _buildMobileInvoiceSummary(context, tr),
            const SizedBox(height: 8),
            _buildCart(context, tr, compactActions: true, expandCartList: false),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSaleControls(BuildContext context, AppLocalizations tr, List<Product> products) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: VentioResponsive.cardInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBarcodeStation(context, tr, products: products, embedded: true),
            if (_scannerActive) ...[
              const SizedBox(height: 10),
              _buildEmbeddedScannerPreview(),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runAlignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _MobileSaleAction(icon: Icons.search, label: tr.text('search'), onTap: () => _showProductSearchSheet(products)),
                _MobileSaleAction(icon: Icons.grid_view_rounded, label: tr.text('quick_products'), onTap: () => _showQuickProductsSheet(products)),
                _MobileSaleAction(icon: Icons.person_outline, label: tr.text('customer'), onTap: _showCustomerSheet),
                _MobileSaleAction(icon: Icons.percent, label: tr.text('discount'), onTap: _showDiscountSheet),
                _MobileSaleAction(icon: Icons.receipt_long_outlined, label: tr.text('recent_invoices'), onTap: _showInvoicesSheet),
                _MobileSaleAction(icon: Icons.more_horiz, label: tr.text('more'), onTap: _showCheckoutSheet),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileInvoiceSummary(BuildContext context, AppLocalizations tr) {
    final customerName = widget.store.resolveCustomerName(_selectedCustomerId);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$customerName • ${_paymentMethodLabel(tr, _paymentMethod)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text('$_itemsCount ${tr.text('items_count')}', style: Theme.of(context).textTheme.bodyMedium)),
                Text(formatUsdReferenceAmount(_total, widget.store.storeProfile), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _paymentMethodLabel(AppLocalizations tr, String method) {
    switch (method) {
      case 'Card':
        return tr.text('payment_card');
      case 'Transfer':
        return tr.text('payment_transfer');
      case 'Mixed':
        return tr.text('payment_mixed');
      case 'Cash':
      default:
        return tr.text('payment_cash');
    }
  }


  void _toggleManualBarcodeInput() {
    setState(() => _manualBarcodeInput = !_manualBarcodeInput);
    if (_manualBarcodeInput) {
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _barcodeFocusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  void _restoreScannerMode() {
    if (_manualBarcodeInput) {
      setState(() => _manualBarcodeInput = false);
    }
    _barcodeFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  bool get _canUseCameraScanner =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _scanBarcodeWithCamera() async {
    setState(() => _scannerActive = !_scannerActive);
  }

  void _handleEmbeddedBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now();
      if (_lastScannedCode == code && _lastScannedAt != null && now.difference(_lastScannedAt!) < const Duration(milliseconds: 1500)) {
        return;
      }
      _lastScannedCode = code;
      _lastScannedAt = now;
      _barcodeController.text = code;
      _addByCode(code);
      return;
    }
  }

  Widget _buildEmbeddedScannerPreview() {
    if (!_canUseCameraScanner || !_scannerActive) return const SizedBox.shrink();
    final tr = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scannerHeight = VentioResponsive.adaptiveWidth(
      context,
      mobile: 132,
      tablet: 150,
      desktop: 170,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.center_focus_strong_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tr.text('inline_barcode_scanner'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: tr.text('stop_camera_scanner'),
                  onPressed: _scanBarcodeWithCamera,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Container(
            height: scannerHeight,
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  fit: BoxFit.cover,
                  onDetect: _handleEmbeddedBarcode,
                ),
                IgnorePointer(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final frameWidth = VentioResponsive.clampToScreen(
                          context,
                          constraints.maxWidth * 0.62,
                          min: 150,
                          horizontalPadding: 48,
                        );
                        return Container(
                          width: frameWidth,
                          height: (frameWidth * 0.40).clamp(64, 90).toDouble(),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeStation(BuildContext context, AppLocalizations tr, {required List<Product> products, bool embedded = false}) {
    return Container(
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final field = TextField(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            autofocus: false,
            readOnly: false,
            showCursor: _manualBarcodeInput,
            enableInteractiveSelection: _manualBarcodeInput,
            keyboardType: _manualBarcodeInput ? TextInputType.text : TextInputType.none,
            textInputAction: TextInputAction.done,
            onTap: () {
              if (!_manualBarcodeInput) {
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }
            },
            decoration: InputDecoration(
              labelText: tr.text('scan_barcode'),
              hintText: tr.text('scan_barcode_hint'),
              prefixIcon: const Icon(Icons.qr_code_2),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _manualBarcodeInput ? tr.text('hide_keyboard') : tr.text('manual_input'),
                    onPressed: _toggleManualBarcodeInput,
                    icon: Icon(_manualBarcodeInput ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined),
                  ),
                  IconButton(
                    tooltip: tr.text('search_product'),
                    onPressed: () => _showProductSearchSheet(products),
                    icon: const Icon(Icons.search),
                  ),
                  if (_canUseCameraScanner)
                    IconButton(
                      tooltip: _scannerActive ? tr.text('stop_camera_scanner') : tr.text('start_camera_scanner'),
                      onPressed: _scanBarcodeWithCamera,
                      icon: Icon(_scannerActive ? Icons.videocam_off_outlined : Icons.camera_alt_outlined),
                    ),
                  IconButton(
                    tooltip: tr.text('clear'),
                    onPressed: () {
                      _barcodeController.clear();
                      if (_manualBarcodeInput) {
                        _barcodeFocusNode.requestFocus();
                      } else {
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      }
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ),
            onSubmitted: _addByCode,
          );
          final button = FilledButton.icon(onPressed: () => _addByCode(_barcodeController.text), icon: const Icon(Icons.add_shopping_cart), label: Text(tr.text('add_to_cart')));
          final preview = embedded ? const SizedBox.shrink() : _buildEmbeddedScannerPreview();
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 8),
                button,
                if (!embedded && _scannerActive) preview,
              ],
            );
          }
          return Column(
            children: [
              Row(children: [const Icon(Icons.qr_code_scanner, size: 32), const SizedBox(width: 12), Expanded(child: field), const SizedBox(width: 12), button]),
              if (!embedded && _scannerActive) preview,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCart(
    BuildContext context,
    AppLocalizations tr, {
    bool compactActions = false,
    bool showTotals = true,
    bool showActions = true,
    bool expandCartList = true,
  }) {
    Widget cartList({required bool shrinkWrap, required ScrollPhysics? physics}) {
      return ListView.separated(
        shrinkWrap: shrinkWrap,
        primary: false,
        physics: physics,
        itemCount: _cart.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _cart[index];
          return LayoutBuilder(
            builder: (context, constraints) {
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: tr.text('decrease_qty'),
                    onPressed: item.quantity > 1 ? () => _changeCartQuantity(index, item.quantity - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(width: 28, child: Text('${item.quantity}', textAlign: TextAlign.center)),
                  IconButton(
                    tooltip: tr.text('increase_qty'),
                    onPressed: item.quantity < item.product.stock ? () => _changeCartQuantity(index, item.quantity + 1) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    tooltip: tr.text('delete'),
                    onPressed: () => setState(() => _cart.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              );
              if (constraints.maxWidth < 520) {
                return InkWell(
                  onTap: () => _showQuantitySheet(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text('${item.product.code} • ${formatUsdReferenceAmount(item.product.price, widget.store.storeProfile)} • ${tr.text('stock')}: ${item.product.stock}'),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    ),
                  ),
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.product.name),
                subtitle: Text('${item.product.code} • ${formatUsdReferenceAmount(item.product.price, widget.store.storeProfile)} • ${tr.text('stock')}: ${item.product.stock}'),
                onTap: () => _showQuantitySheet(index),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: VentioResponsive.adaptiveWidth(context, mobile: 144, tablet: 164, desktop: 178)),
                  child: actions,
                ),
              );
            },
          );
        },
      );
    }

    final Widget cartContent;
    if (_cart.isEmpty) {
      final emptyState = Center(child: Text(tr.text('invoice_empty')));
      cartContent = expandCartList
          ? Expanded(child: emptyState)
          : SizedBox(height: 140, child: emptyState);
    } else {
      final list = cartList(
        shrinkWrap: !expandCartList,
        physics: expandCartList ? null : const NeverScrollableScrollPhysics(),
      );
      cartContent = expandCartList ? Expanded(child: list) : list;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(tr.text('cart'), style: Theme.of(context).textTheme.titleLarge),
                Chip(label: Text('${tr.text('items')}: $_itemsCount')),
                if (_cart.isNotEmpty)
                  TextButton.icon(onPressed: () => setState(() => _cart.clear()), icon: const Icon(Icons.delete_sweep_outlined), label: Text(tr.text('clear_cart'))),
                if (_cart.isNotEmpty)
                  TextButton.icon(onPressed: () => setState(() { _heldCart = List<_DraftSaleItem>.from(_cart); _cart.clear(); }), icon: const Icon(Icons.pause_circle_outline), label: Text(tr.text('hold'))),
                if (_heldCart != null && _cart.isEmpty)
                  TextButton.icon(onPressed: () => setState(() { _cart.addAll(_heldCart!); _heldCart = null; }), icon: const Icon(Icons.play_circle_outline), label: Text(tr.text('restore'))),
              ],
            ),
            const SizedBox(height: 8),
            cartContent,
            if (showTotals) ...[
              const Divider(height: 24),
              _totalLine(tr.text('subtotal'), formatUsdReferenceAmount(_subtotal, widget.store.storeProfile)),
              _totalLine(tr.text('discount'), formatUsdReferenceAmount(_discount, widget.store.storeProfile)),
              if (_discount > _subtotal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    tr.text('discount_exceeds_subtotal'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              _totalLine(tr.text('total'), formatUsdReferenceAmount(_total, widget.store.storeProfile), isBold: true),
            ],
            if (showActions) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final primary = FilledButton.icon(onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: true), icon: const Icon(Icons.point_of_sale), label: Text(tr.text('complete_sale_print')));
                  final secondary = OutlinedButton.icon(onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: false), icon: const Icon(Icons.save_outlined), label: Text(tr.text('save_only')));
                  if (constraints.maxWidth < 460) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [primary, const SizedBox(height: 8), secondary]);
                  }
                  return Row(children: [Expanded(child: primary), const SizedBox(width: 12), Expanded(child: secondary)]);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalLine(String title, String value, {bool isBold = false}) {
    final style = isBold ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(title), Text(value, style: style)],
      ),
    );
  }

  Widget _buildInvoicesPanel(BuildContext context, AppLocalizations tr, List<Sale> sales) {
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.text('recent_invoices'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: sales.isEmpty
                  ? EmptyStateCard(icon: Icons.receipt_long_outlined, title: tr.text('no_sales'), subtitle: tr.text('no_sales_desc'))
                  : ListView.separated(
                      itemCount: sales.length > 50 ? 50 : sales.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sale = sales[index];
                        return ExpansionTile(
                          leading: Icon(sale.isCancelled ? Icons.cancel_outlined : Icons.check_circle),
                          title: Text(sale.invoiceNo),
                          subtitle: Text('${sale.customerName} • ${sale.date.toLocal()}'.split('.').first),
                          trailing: Text(sale.isCancelled ? sale.status : formatUsdReferenceAmount(sale.total, widget.store.storeProfile)),
                          children: [
                            ...sale.items.map(
                              (item) => ListTile(
                                dense: true,
                                title: Text(item.productName),
                                subtitle: Text('${tr.text('quantity')}: ${item.quantity} × ${formatUsdReferenceAmount(item.unitPrice, widget.store.storeProfile)}'),
                                trailing: Text(formatUsdReferenceAmount(item.lineTotal, widget.store.storeProfile)),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _handleInvoiceAction(() => InvoicePdfService.printInvoice(sale: sale, profile: widget.store.storeProfile)),
                                    icon: const Icon(Icons.print_outlined),
                                    label: Text(tr.text('print_invoice')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _handleInvoiceAction(() => InvoicePdfService.shareInvoice(sale: sale, profile: widget.store.storeProfile)),
                                    icon: const Icon(Icons.share_outlined),
                                    label: Text(tr.text('share_pdf')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: (!sale.isCancelled && widget.store.canDeleteOrCancel) ? () => _cancelSale(context, sale) : null,
                                    icon: const Icon(Icons.assignment_return_outlined),
                                    label: Text(tr.text('cancel_return')),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeCartQuantity(int index, int quantity) {
    if (index < 0 || index >= _cart.length) return;
    final item = _cart[index];
    final cleanQuantity = quantity.clamp(1, item.product.stock).toInt();
    setState(() {
      _cart[index] = item.copyWith(quantity: cleanQuantity);
    });
  }

  Future<void> _showQuantitySheet(int index) async {
    if (index < 0 || index >= _cart.length) return;
    final tr = AppLocalizations.of(context);
    final item = _cart[index];
    final controller = TextEditingController(text: '${item.quantity}');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.product.name, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: tr.text('quantity')),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final current = int.tryParse(controller.text) ?? item.quantity;
                          controller.text = '${(current - 1).clamp(1, item.product.stock)}';
                          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                        },
                        icon: const Icon(Icons.remove),
                        label: Text(tr.text('decrease_qty')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final current = int.tryParse(controller.text) ?? item.quantity;
                          controller.text = '${(current + 1).clamp(1, item.product.stock)}';
                          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tr.text('increase_qty')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    final quantity = int.tryParse(controller.text) ?? item.quantity;
                    Navigator.pop(sheetContext);
                    _changeCartQuantity(index, quantity);
                    FocusScope.of(context).unfocus();
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  void _showQuickProductsSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    _ensureQuickPages(products, tr);
    var sheetSelectedPageIndex = _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          _ensureQuickPages(products, tr);
          sheetSelectedPageIndex = sheetSelectedPageIndex.clamp(0, _quickPages.length - 1).toInt();
          final page = _quickPages[sheetSelectedPageIndex];

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(tr.text('quick_product_grid'), style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                          tooltip: tr.text('close'),
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickPages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final selected = index == sheetSelectedPageIndex;
                          return InputChip(
                            label: Text(_quickPages[index].name),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => _selectedQuickPageIndex = index);
                              setModalState(() => sheetSelectedPageIndex = index);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth > 520 ? 3 : 2;
                          return GridView.builder(
                            itemCount: page.slots.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.18,
                            ),
                            itemBuilder: (context, index) {
                              final slot = page.slots[index];
                              final product = slot.productId == null ? null : _productById(slot.productId!);
                              final isEmpty = product == null;
                              return _buildQuickProductTile(context, tr, page, index, slot, product, isEmpty);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProductSearchSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: _search);
    var query = _search;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final filteredProducts = products.where((product) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return product.name.toLowerCase().contains(q) || product.code.toLowerCase().contains(q) || product.category.toLowerCase().contains(q);
          }).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr.text('search_product'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: tr.text('search_product')),
                      onChanged: (value) => setModalState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? Center(child: Text(tr.text('no_products')))
                          : ListView.separated(
                              itemCount: filteredProducts.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                return ListTile(
                                  title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text('${product.code} • ${tr.text('stock')}: ${product.stock}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Text(formatUsdReferenceAmount(product.price, widget.store.storeProfile)),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _search = '';
                                    _searchController.clear();
                                    FocusScope.of(context).unfocus();
                                    _addProduct(product);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  void _showCustomerSheet() {
    final tr = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(tr.text('customer'), style: Theme.of(context).textTheme.titleLarge)),
            ...widget.store.customers.map((customer) {
              final selectedCustomerId = widget.store.sanitizeSelectedCustomerId(_selectedCustomerId);
              final isSelected = customer.id == selectedCustomerId;
              return ListTile(
                leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(customer.name),
                selected: isSelected,
                onTap: () {
                  setState(() => _selectedCustomerId = widget.store.sanitizeSelectedCustomerId(customer.id));
                  Navigator.pop(sheetContext);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showDiscountSheet() {
    final tr = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('discount'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _discountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))],
                decoration: InputDecoration(labelText: tr.text('discount')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(sheetContext);
                  FocusScope.of(context).unfocus();
                },
                child: Text(tr.text('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInvoicesSheet() {
    final tr = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.76,
            child: _buildInvoicesPanel(sheetContext, tr, widget.store.sales),
          ),
        ),
      ),
    );
  }

  void _showCheckoutSheet() {
    final tr = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr.text('complete_sale'), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: widget.store.sanitizeSelectedCustomerId(_selectedCustomerId),
                    items: widget.store.customers.map((customer) => DropdownMenuItem<String>(value: customer.id, child: Text(customer.name))).toList(),
                    decoration: InputDecoration(labelText: tr.text('customer')),
                    onChanged: (value) => setState(() => _selectedCustomerId = widget.store.sanitizeSelectedCustomerId(value)),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _discountController,
                    decoration: InputDecoration(labelText: tr.text('discount')),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))],
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      setState(() {});
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: InputDecoration(labelText: tr.text('payment')),
                    items: [
                      DropdownMenuItem(value: 'Cash', child: Text(tr.text('cash'))),
                      DropdownMenuItem(value: 'Card', child: Text(tr.text('card'))),
                      DropdownMenuItem(value: 'Transfer', child: Text(tr.text('transfer'))),
                      DropdownMenuItem(value: 'Mixed', child: Text(tr.text('mixed'))),
                    ],
                    onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
                  ),
                  const SizedBox(height: 14),
                  _totalLine(tr.text('subtotal'), formatUsdReferenceAmount(_subtotal, widget.store.storeProfile)),
                  _totalLine(tr.text('discount'), formatUsdReferenceAmount(_discount, widget.store.storeProfile)),
                  _totalLine(tr.text('total'), formatUsdReferenceAmount(_total, widget.store.storeProfile), isBold: true),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _cart.isEmpty ? null : () {
                      Navigator.pop(sheetContext);
                      _saveCurrentInvoice(printAfterSave: true);
                    },
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(tr.text('complete_sale_print')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _cart.isEmpty ? null : () {
                      Navigator.pop(sheetContext);
                      _saveCurrentInvoice(printAfterSave: false);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(tr.text('save_only')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelSale(BuildContext context, Sale sale) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text(tr.text('cancel_return_confirm').replaceAll('{invoice}', sale.invoiceNo)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr.text('cancel_invoice'))),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.store.cancelSale(sale.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('invoice_cancelled_stock_restored'))));
    }
  }

  _BarcodeAddResult _addProduct(Product product, {bool showBarcodeFeedback = false}) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canSell) {
      if (showBarcodeFeedback) {
        _showBarcodeAddFeedback(_BarcodeAddResult.notAllowed);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('role_not_allowed_to_sell'))));
      }
      _restoreScannerMode();
      return _BarcodeAddResult.notAllowed;
    }

    if (product.stock <= 0) {
      if (showBarcodeFeedback) {
        _showBarcodeAddFeedback(_BarcodeAddResult.outOfStock);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('barcode_out_of_stock'))));
      }
      _restoreScannerMode();
      return _BarcodeAddResult.outOfStock;
    }

    final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);
    var result = _BarcodeAddResult.added;
    setState(() {
      if (existingIndex == -1) {
        _cart.insert(0, _DraftSaleItem(product: product, quantity: 1));
      } else if (_cart[existingIndex].quantity < product.stock) {
        _cart[existingIndex] = _cart[existingIndex].copyWith(quantity: _cart[existingIndex].quantity + 1);
      } else {
        result = _BarcodeAddResult.stockLimitReached;
      }
    });

    if (showBarcodeFeedback) {
      _showBarcodeAddFeedback(result);
    } else if (result == _BarcodeAddResult.stockLimitReached) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('stock_limit_reached'))));
    }

    _restoreScannerMode();
    return result;
  }

  _BarcodeAddResult _addByCode(String code) {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      _restoreScannerMode();
      return _BarcodeAddResult.empty;
    }

    final product = widget.store.findProductByCode(cleanCode);
    if (product == null) {
      _barcodeController.clear();
      _showBarcodeAddFeedback(_BarcodeAddResult.notFound);
      _restoreScannerMode();
      return _BarcodeAddResult.notFound;
    }

    if (product.stock <= 0) {
      _barcodeController.clear();
      _showBarcodeAddFeedback(_BarcodeAddResult.outOfStock);
      _restoreScannerMode();
      return _BarcodeAddResult.outOfStock;
    }

    _barcodeController.clear();
    return _addProduct(product, showBarcodeFeedback: true);
  }

  void _showBarcodeAddFeedback(_BarcodeAddResult result) {
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (result) {
      case _BarcodeAddResult.added:
        unawaited(BarcodeFeedbackService.play(force: true));
        messenger.showSnackBar(SnackBar(content: Text(tr.text('barcode_product_added'))));
        return;
      case _BarcodeAddResult.notFound:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(SnackBar(content: Text(tr.text('barcode_product_not_registered'))));
        return;
      case _BarcodeAddResult.outOfStock:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(SnackBar(content: Text(tr.text('barcode_out_of_stock'))));
        return;
      case _BarcodeAddResult.stockLimitReached:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(SnackBar(content: Text(tr.text('barcode_stock_limit_reached'))));
        return;
      case _BarcodeAddResult.notAllowed:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(SnackBar(content: Text(tr.text('role_not_allowed_to_sell'))));
        return;
      case _BarcodeAddResult.empty:
        return;
    }
  }

  Future<void> _saveCurrentInvoice({required bool printAfterSave}) async {
    if (_cart.isEmpty) return;
    if (_discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('discount_exceeds_subtotal'))));
      return;
    }

    late final Sale sale;
    try {
      sale = await widget.store.createSale(
        customerName: widget.store.resolveCustomerName(_selectedCustomerId),
        discount: _discount,
        paymentMethod: _paymentMethod,
        items: _cart
            .map(
              (item) => SaleItem(
                productId: item.product.id,
                productName: item.product.name,
                unitPrice: item.product.price,
                quantity: item.quantity,
                unitCost: item.product.cost,
              ),
            )
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('sale_validation_failed'))));
      return;
    }

    if (!mounted) return;

    setState(() {
      _cart.clear();
      _discountController.clear();
      _searchController.clear();
      _barcodeController.clear();
      _search = '';
    });
    _restoreScannerMode();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('invoice_created_successfully'))));

    if (printAfterSave) {
      await _handleInvoiceAction(() => InvoicePdfService.printInvoice(sale: sale, profile: widget.store.storeProfile));
    }
  }

  Future<void> _handleInvoiceAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('pdf_action_failed'))));
    }
  }
}


class _MobileSaleAction extends StatelessWidget {
  const _MobileSaleAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _QuickProductSlot {
  const _QuickProductSlot({this.productId, this.shortName});

  final String? productId;
  final String? shortName;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'shortName': shortName,
      };

  factory _QuickProductSlot.fromJson(Map<String, dynamic> json) => _QuickProductSlot(
        productId: json['productId'] as String?,
        shortName: json['shortName'] as String?,
      );
}

class _QuickProductPage {
  _QuickProductPage({required this.name, required this.slots});

  String name;
  final List<_QuickProductSlot> slots;

  Map<String, dynamic> toJson() => {
        'name': name,
        'slots': slots.map((slot) => slot.toJson()).toList(),
      };

  factory _QuickProductPage.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'];
    final slots = rawSlots is List
        ? rawSlots.whereType<Map<String, dynamic>>().map(_QuickProductSlot.fromJson).toList()
        : <_QuickProductSlot>[];
    while (slots.length < 12) {
      slots.add(const _QuickProductSlot());
    }
    if (slots.length > 12) slots.removeRange(12, slots.length);
    return _QuickProductPage(
      name: (json['name'] as String?)?.trim().isNotEmpty == true ? (json['name'] as String).trim() : 'Favorites',
      slots: slots,
    );
  }
}

class _DraftSaleItem {
  const _DraftSaleItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  double get lineTotal => quantity * product.price;

  _DraftSaleItem copyWith({Product? product, int? quantity}) {
    return _DraftSaleItem(product: product ?? this.product, quantity: quantity ?? this.quantity);
  }
}
