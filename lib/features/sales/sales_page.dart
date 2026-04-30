import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

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

  final List<_DraftSaleItem> _cart = [];
  String _selectedCustomerId = AppStore.walkInCustomerId;
  String _paymentMethod = 'Cash';
  String _search = '';
  List<_DraftSaleItem>? _heldCart;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = AppStore.walkInCustomerId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _barcodeFocusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _discountController.dispose();
    _barcodeFocusNode.dispose();
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1120;
          final posPanel = _buildPosPanel(context, tr, products, isWide: isWide);
          final invoicesPanel = _buildInvoicesPanel(context, tr, sales);

          return Column(
            children: [
              AppSectionHeader(
                title: tr.text('pos_terminal'),
                subtitle: tr.text('pos_terminal_desc'),
                action: FilledButton.icon(
                  onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: true),
                  icon: const Icon(Icons.point_of_sale),
                  label: Text(tr.text('complete_sale')),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: posPanel),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: invoicesPanel),
                        ],
                      )
                    : ListView(
                        children: [
                          ConstrainedBox(constraints: const BoxConstraints(minHeight: 760), child: posPanel),
                          const SizedBox(height: 16),
                          ConstrainedBox(constraints: const BoxConstraints(minHeight: 420), child: invoicesPanel),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPosPanel(BuildContext context, AppLocalizations tr, List<Product> products, {required bool isWide}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBarcodeStation(context, tr),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    value: widget.store.sanitizeSelectedCustomerId(_selectedCustomerId),
                    items: widget.store.customers
                        .map((customer) => DropdownMenuItem<String>(value: customer.id, child: Text(customer.name)))
                        .toList(),
                    decoration: InputDecoration(labelText: tr.text('customer')),
                    onChanged: (value) => setState(() => _selectedCustomerId = widget.store.sanitizeSelectedCustomerId(value)),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextFormField(
                    controller: _discountController,
                    decoration: InputDecoration(labelText: tr.text('discount')),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment'),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'Card', child: Text('Card')),
                      DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                      DropdownMenuItem(value: 'Mixed', child: Text('Mixed')),
                    ],
                    onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: tr.text('search_product'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(() {
                                _search = '';
                                _searchController.clear();
                              }),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: isWide
                  ? Row(
                      children: [
                        Expanded(flex: 6, child: _buildProductPicker(context, tr, products)),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: _buildCart(context, tr)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(flex: 5, child: _buildCart(context, tr)),
                        const SizedBox(height: 16),
                        Expanded(flex: 4, child: _buildProductPicker(context, tr, products)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeStation(BuildContext context, AppLocalizations tr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.45),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_scanner, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: tr.text('scan_barcode'),
                hintText: tr.text('scan_barcode_hint'),
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: IconButton(
                  onPressed: () {
                    _barcodeController.clear();
                    _barcodeFocusNode.requestFocus();
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
              onSubmitted: _addByCode,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _addByCode(_barcodeController.text),
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(tr.text('add_to_cart')),
          ),
        ],
      ),
    );
  }

  Widget _buildProductPicker(BuildContext context, AppLocalizations tr, List<Product> products) {
    if (products.isEmpty) {
      return EmptyStateCard(icon: Icons.inventory_2_outlined, title: tr.text('no_products'), subtitle: tr.text('no_products_desc'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(tr.text('quick_products'), style: Theme.of(context).textTheme.titleMedium)),
            Text('${products.length}'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 700 ? 3 : 2;
              return GridView.builder(
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _addProduct(product),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            Text(product.code, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${tr.text('stock')}: ${product.stock}'),
                            const SizedBox(height: 8),
                            Text(
                              formatCurrency(product.price, currency: widget.store.storeProfile.currency),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCart(BuildContext context, AppLocalizations tr) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr.text('cart'), style: Theme.of(context).textTheme.titleLarge)),
                Chip(label: Text('${tr.text('items')}: $_itemsCount')),
                const SizedBox(width: 8),
                if (_cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _cart.clear()),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(tr.text('clear_cart')),
                  ),
                if (_cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _heldCart = List<_DraftSaleItem>.from(_cart);
                      _cart.clear();
                    }),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Hold'),
                  ),
                if (_heldCart != null && _cart.isEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _cart.addAll(_heldCart!);
                      _heldCart = null;
                    }),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Restore'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _cart.isEmpty
                  ? Center(child: Text(tr.text('invoice_empty')))
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.product.name),
                          subtitle: Text('${item.product.code} • ${formatCurrency(item.product.price, currency: widget.store.storeProfile.currency)} • ${tr.text('stock')}: ${item.product.stock}'),
                          trailing: SizedBox(
                            width: 178,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: tr.text('decrease_qty'),
                                  onPressed: item.quantity > 1 ? () => setState(() => _cart[index] = item.copyWith(quantity: item.quantity - 1)) : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                SizedBox(width: 28, child: Text('${item.quantity}', textAlign: TextAlign.center)),
                                IconButton(
                                  tooltip: tr.text('increase_qty'),
                                  onPressed: item.quantity < item.product.stock ? () => setState(() => _cart[index] = item.copyWith(quantity: item.quantity + 1)) : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                IconButton(
                                  tooltip: tr.text('delete'),
                                  onPressed: () => setState(() => _cart.removeAt(index)),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 24),
            _totalLine(tr.text('subtotal'), formatCurrency(_subtotal, currency: widget.store.storeProfile.currency)),
            _totalLine(tr.text('discount'), formatCurrency(_discount, currency: widget.store.storeProfile.currency)),
            if (_discount > _subtotal)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  tr.text('discount_exceeds_subtotal'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            _totalLine(tr.text('total'), formatCurrency(_total, currency: widget.store.storeProfile.currency), isBold: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: true),
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(tr.text('complete_sale_print')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cart.isEmpty ? null : () => _saveCurrentInvoice(printAfterSave: false),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(tr.text('save_only')),
                  ),
                ),
              ],
            ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.text('recent_invoices'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: sales.isEmpty
                  ? EmptyStateCard(icon: Icons.receipt_long_outlined, title: tr.text('no_sales'), subtitle: tr.text('no_sales_desc'))
                  : ListView.separated(
                      itemCount: sales.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sale = sales[index];
                        return ExpansionTile(
                          leading: Icon(sale.isCancelled ? Icons.cancel_outlined : Icons.check_circle),
                          title: Text(sale.invoiceNo),
                          subtitle: Text('${sale.customerName} • ${sale.date.toLocal()}'.split('.').first),
                          trailing: Text(sale.isCancelled ? sale.status : formatCurrency(sale.total, currency: widget.store.storeProfile.currency)),
                          children: [
                            ...sale.items.map(
                              (item) => ListTile(
                                dense: true,
                                title: Text(item.productName),
                                subtitle: Text('${tr.text('quantity')}: ${item.quantity} × ${formatCurrency(item.unitPrice, currency: widget.store.storeProfile.currency)}'),
                                trailing: Text(formatCurrency(item.lineTotal, currency: widget.store.storeProfile.currency)),
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
                                    label: const Text('Cancel / Return'),
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

  Future<void> _cancelSale(BuildContext context, Sale sale) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('Cancel/return invoice ${sale.invoiceNo} and restore its stock?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel invoice')),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.store.cancelSale(sale.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice cancelled and stock restored')));
    }
  }

  void _addProduct(Product product) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canSell) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current role is not allowed to sell.')));
      return;
    }
    final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);
    setState(() {
      if (existingIndex == -1) {
        _cart.add(_DraftSaleItem(product: product, quantity: 1));
      } else if (_cart[existingIndex].quantity < product.stock) {
        _cart[existingIndex] = _cart[existingIndex].copyWith(quantity: _cart[existingIndex].quantity + 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('stock_limit_reached'))));
      }
    });
    _barcodeFocusNode.requestFocus();
  }

  void _addByCode(String code) {
    final tr = AppLocalizations.of(context);
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      _barcodeFocusNode.requestFocus();
      return;
    }
    final product = widget.store.findProductByCode(cleanCode);
    if (product == null || product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('product_code_not_found'))));
      _barcodeController.clear();
      _barcodeFocusNode.requestFocus();
      return;
    }
    _barcodeController.clear();
    _addProduct(product);
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
    _barcodeFocusNode.requestFocus();

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

class _DraftSaleItem {
  const _DraftSaleItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  double get lineTotal => quantity * product.price;

  _DraftSaleItem copyWith({Product? product, int? quantity}) {
    return _DraftSaleItem(product: product ?? this.product, quantity: quantity ?? this.quantity);
  }
}
