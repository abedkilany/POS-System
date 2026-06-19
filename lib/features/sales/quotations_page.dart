import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/sale_item.dart';
import '../../models/sale_quotation.dart';
import '../../widgets/empty_state_card.dart';

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  Future<void> _createQuotation() async {
    final tr = AppLocalizations.of(context);
    final result = await showDialog<_QuotationDraft>(
      context: context,
      builder: (context) => _QuotationDialog(store: widget.store),
    );
    if (result == null) return;
    try {
      await widget.store.createSaleQuotation(
        customerName: result.customerName,
        customerId: result.customerId,
        items: result.items,
        discount: result.discount,
        invoiceCurrency: result.invoiceCurrency,
        note: result.note,
        validUntil: null,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('quotation_saved'))));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _convertQuotation(SaleQuotation quotation) async {
    final tr = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('convert_quotation')),
        content: Text(tr.format('convert_quotation_question', {'quotationNo': quotation.quotationNo})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('convert'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final sale = await widget.store.convertSaleQuotationToSale(quotation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.format('quotation_invoice_created', {'invoiceNo': sale.invoiceNo}))),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteQuotation(SaleQuotation quotation) async {
    final tr = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete_quotation')),
        content: Text(tr.format('delete_quotation_question', {'quotationNo': quotation.quotationNo})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirm == true) await widget.store.deleteSaleQuotation(quotation.id);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final quotations = widget.store.saleQuotations;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('quotations')),
        actions: [IconButton(onPressed: _createQuotation, icon: const Icon(Icons.add), tooltip: tr.text('new_quotation'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createQuotation,
        icon: const Icon(Icons.add),
        label: Text(tr.text('new_quotation')),
      ),
      body: quotations.isEmpty
          ? EmptyStateCard(icon: Icons.request_quote_outlined, title: tr.text('no_quotations'), subtitle: tr.text('no_quotations_desc'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: quotations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final quotation = quotations[index];
                return Card(
                  child: ListTile(
                    leading: Icon(quotation.isConverted ? Icons.check_circle_outline : Icons.request_quote_outlined),
                    title: Text('${quotation.quotationNo} • ${quotation.customerName}'),
                    subtitle: Text('${_localizedStatus(tr, quotation.status)} • ${quotation.items.length} ${tr.text('items')} • ${quotation.total.toStringAsFixed(2)} ${quotation.invoiceCurrency}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: tr.text('convert_to_sale'),
                          onPressed: quotation.isConverted ? null : () => _convertQuotation(quotation),
                          icon: const Icon(Icons.receipt_long),
                        ),
                        IconButton(
                          tooltip: tr.text('delete'),
                          onPressed: quotation.isConverted ? null : () => _deleteQuotation(quotation),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _localizedStatus(AppLocalizations tr, String status) {
  switch (status.toLowerCase()) {
    case 'draft':
      return tr.text('draft');
    case 'converted':
      return tr.text('converted');
    case 'cancelled':
      return tr.text('cancelled');
    default:
      return status;
  }
}

class _QuotationDraft {
  const _QuotationDraft({required this.customerName, required this.customerId, required this.items, required this.discount, required this.invoiceCurrency, required this.note});
  final String customerName, customerId, invoiceCurrency, note;
  final List<SaleItem> items;
  final double discount;
}

class _QuotationDialog extends StatefulWidget {
  const _QuotationDialog({required this.store});
  final AppStore store;

  @override
  State<_QuotationDialog> createState() => _QuotationDialogState();
}

class _QuotationDialogState extends State<_QuotationDialog> {
  String _customerId = AppStore.walkInCustomerId;
  String _invoiceCurrency = 'USD';
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final List<SaleItem> _items = [];

  @override
  void dispose() {
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _addProduct(Product product) {
    final existingIndex = _items.indexWhere((item) => item.productId == product.id);
    setState(() {
      if (existingIndex >= 0) {
        final existing = _items[existingIndex];
        _items[existingIndex] = SaleItem(
          productId: existing.productId,
          productName: existing.productName,
          unitPrice: existing.unitPrice,
          quantity: existing.quantity + 1,
          unitCost: existing.unitCost,
          unitName: existing.unitName,
          baseQuantity: existing.effectiveBaseQuantity + 1,
          conversionToBase: existing.conversionToBase,
        );
      } else {
        _items.add(SaleItem(productId: product.id, productName: product.name, unitPrice: product.usdPrice, quantity: 1, unitCost: product.usdCost, unitName: product.unit, baseQuantity: 1, conversionToBase: 1));
      }
    });
  }

  double get _subtotal => _items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0;
  double get _total => (_subtotal - _discount).clamp(0, double.infinity).toDouble();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final customers = <Customer>[widget.store.walkInCustomer, ...widget.store.customers];
    return AlertDialog(
      title: Text(tr.text('new_quotation')),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _customerId,
                decoration: InputDecoration(labelText: tr.text('customer')),
                items: customers.map((customer) => DropdownMenuItem(value: customer.id, child: Text(customer.name))).toList(),
                onChanged: (value) => setState(() => _customerId = value ?? AppStore.walkInCustomerId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _invoiceCurrency,
                decoration: InputDecoration(labelText: tr.text('currency')),
                items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'LBP', child: Text('LBP'))],
                onChanged: (value) => setState(() => _invoiceCurrency = value ?? 'USD'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: tr.text('add_product')),
                items: widget.store.products.map((product) => DropdownMenuItem(value: product.id, child: Text(product.name))).toList(),
                onChanged: (value) {
                  Product? product;
                  for (final item in widget.store.products) {
                    if (item.id == value) {
                      product = item;
                      break;
                    }
                  }
                  if (product != null) _addProduct(product);
                },
              ),
              const SizedBox(height: 12),
              ..._items.map((item) => ListTile(
                    dense: true,
                    title: Text(item.productName),
                    subtitle: Text('${item.quantity.toStringAsFixed(0)} x ${item.unitPrice.toStringAsFixed(2)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() => _items.remove(item)),
                    ),
                  )),
              TextField(controller: _discountController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr.text('discount')), onChanged: (_) => setState(() {})),
              TextField(controller: _noteController, decoration: InputDecoration(labelText: tr.text('notes'))),
              const SizedBox(height: 12),
              Text('${tr.text('total')}: ${_total.toStringAsFixed(2)} $_invoiceCurrency', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: _items.isEmpty
              ? null
              : () {
                  final customer = customers.firstWhere((item) => item.id == _customerId, orElse: () => widget.store.walkInCustomer);
                  Navigator.pop(context, _QuotationDraft(customerName: customer.name, customerId: customer.id, items: List<SaleItem>.from(_items), discount: _discount, invoiceCurrency: _invoiceCurrency, note: _noteController.text));
                },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }
}
