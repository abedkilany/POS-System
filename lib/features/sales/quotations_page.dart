import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/business_revision_service.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/local_database_service.dart';
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
  Future<List<SaleQuotation>?>? _quotationsFuture;
  String _quotationsFutureKey = '';

  Future<List<SaleQuotation>?> _loadQuotations() async {
    final key = '${BusinessRevisionService.instance.salesRevision}|quotations';
    if (_quotationsFuture == null || _quotationsFutureKey != key) {
      _quotationsFutureKey = key;
      _quotationsFuture = () async {
        final page = await SaleRepository.queryQuotationsPage(limit: 500);
        return page?.items;
      }();
    }
    return _quotationsFuture!;
  }

  Future<void> _createQuotation() async {
    if (!widget.store.canManageQuotations) return;
    final tr = AppLocalizations.of(context);
    final result = await showDialog<_QuotationDraft>(
      context: context,
      builder: (context) => _QuotationDialog(store: widget.store),
    );
    if (result == null) return;
    try {
      await SaleRepository.createSaleQuotation(context: 
        widget.store,
        customerName: result.customerName,
        customerId: result.customerId,
        items: result.items,
        discount: result.discount,
        invoiceCurrency: result.invoiceCurrency,
        note: result.note,
        validUntil: null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr.text('quotation_saved'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _convertQuotation(SaleQuotation quotation) async {
    if (!widget.store.canManageQuotations) return;
    final tr = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('convert_quotation')),
        content: Text(tr.format('convert_quotation_question',
            {'quotationNo': quotation.quotationNo})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('convert'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final sale = await SaleRepository.convertSaleQuotationToSale(
        widget.store,
        quotation.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr.format(
                'quotation_invoice_created', {'invoiceNo': sale.invoiceNo})),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deleteQuotation(SaleQuotation quotation) async {
    if (!widget.store.canManageQuotations) return;
    final tr = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete_quotation')),
        content: Text(tr.format('delete_quotation_question',
            {'quotationNo': quotation.quotationNo})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirm == true) {
      await SaleRepository.deleteSaleQuotation(widget.store, quotation.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewQuotations) {
      return const _AccessDeniedScaffold(
        title: 'Quotations',
        message: 'You do not have access to quotation records.',
      );
    }
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return FutureBuilder<List<SaleQuotation>?>(
      future: _loadQuotations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final quotations = snapshot.data ?? const <SaleQuotation>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(tr.text('quotations')),
            actions: [
              IconButton(
                onPressed:
                    widget.store.canManageQuotations ? _createQuotation : null,
                icon: const Icon(Icons.add),
                tooltip: tr.text('new_quotation'),
              )
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed:
                widget.store.canManageQuotations ? _createQuotation : null,
            icon: const Icon(Icons.add),
            label: Text(tr.text('new_quotation')),
          ),
          body: quotations.isEmpty
              ? EmptyStateCard(
                  icon: Icons.request_quote_outlined,
                  title: tr.text('no_quotations'),
                  subtitle: tr.text('no_quotations_desc'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: quotations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final quotation = quotations[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(quotation.isConverted
                            ? Icons.check_circle_outline
                            : Icons.request_quote_outlined),
                        title: Text(
                            '${quotation.quotationNo} â€¢ ${quotation.customerName}'),
                        subtitle: Text(
                          '${_localizedStatus(tr, quotation.status)} â€¢ ${quotation.items.length} ${tr.text('items')} â€¢ ${quotation.total.toStringAsFixed(2)} ${quotation.invoiceCurrency}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: tr.text('convert_to_sale'),
                              onPressed: quotation.isConverted ||
                                      !widget.store.canManageQuotations
                                  ? null
                                  : () => _convertQuotation(quotation),
                              icon: const Icon(Icons.receipt_long),
                            ),
                            IconButton(
                              tooltip: tr.text('delete'),
                              onPressed: quotation.isConverted ||
                                      !widget.store.canManageQuotations
                                  ? null
                                  : () => _deleteQuotation(quotation),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
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
  const _QuotationDraft({
    required this.customerName,
    required this.customerId,
    required this.items,
    required this.discount,
    required this.invoiceCurrency,
    required this.note,
  });

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
  late final Future<void> _loadFuture;
  Map<String, Customer> _customerById = <String, Customer>{};
  List<DropdownMenuItem<String>> _customerItems = <DropdownMenuItem<String>>[];
  Map<String, Product> _productById = <String, Product>{};
  List<DropdownMenuItem<String>> _productItems = <DropdownMenuItem<String>>[];

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<void> _loadData() async {
    final customerPage = await CustomerRepository.queryPage(
      limit: 500,
      includeWalkIn: true,
    );
    final productPage = await ProductRepository.queryPage(
      limit: 500,
      activeOnly: true,
      stockTrackedOnly: true,
    );
    final customers = <Customer>[
      widget.store.walkInCustomer,
      ...?customerPage?.items
          .where((item) => item.id != AppStore.walkInCustomerId),
    ];
    final products = productPage?.items ?? const <Product>[];
    if (!mounted) return;
    setState(() {
      _customerById = {for (final customer in customers) customer.id: customer};
      _customerItems = [
        for (final customer in customers)
          DropdownMenuItem(value: customer.id, child: Text(customer.name)),
      ];
      _productById = {for (final product in products) product.id: product};
      _productItems = [
        for (final product in products)
          DropdownMenuItem(value: product.id, child: Text(product.name)),
      ];
    });
  }

  @override
  void dispose() {
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _addProduct(Product product) {
    final existingIndex =
        _items.indexWhere((item) => item.productId == product.id);
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
        _items.add(
          SaleItem(
            productId: product.id,
            productName: product.name,
            unitPrice: product.price,
            quantity: 1,
            unitCost: product.usdCost,
            unitName: product.unit,
            baseQuantity: 1,
            conversionToBase: 1,
          ),
        );
      }
    });
  }

  double get _subtotal =>
      _items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0;
  double get _total =>
      (_subtotal - _discount).clamp(0, double.infinity).toDouble();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
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
                    items: _customerItems,
                    onChanged: (value) => setState(
                        () => _customerId = value ?? AppStore.walkInCustomerId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _invoiceCurrency,
                    decoration: InputDecoration(labelText: tr.text('currency')),
                    items: const [
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'LBP', child: Text('LBP'))
                    ],
                    onChanged: (value) =>
                        setState(() => _invoiceCurrency = value ?? 'USD'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration:
                        InputDecoration(labelText: tr.text('add_product')),
                    items: _productItems,
                    onChanged: (value) {
                      final product = value == null ? null : _productById[value];
                      if (product != null) _addProduct(product);
                    },
                  ),
                  const SizedBox(height: 12),
                  ..._items.map(
                    (item) => ListTile(
                      dense: true,
                      title: Text(item.productName),
                      subtitle: Text(
                          '${item.quantity.toStringAsFixed(0)} x ${item.unitPrice.toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() => _items.remove(item)),
                      ),
                    ),
                  ),
                  TextField(
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr.text('discount')),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _noteController,
                    decoration: InputDecoration(labelText: tr.text('notes')),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${tr.text('total')}: ${_total.toStringAsFixed(2)} $_invoiceCurrency',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: _items.isEmpty
                  ? null
                  : () {
                      final customer = _customerById[_customerId] ??
                          widget.store.walkInCustomer;
                      Navigator.pop(
                        context,
                        _QuotationDraft(
                          customerName: customer.name,
                          customerId: customer.id,
                          items: List<SaleItem>.from(_items),
                          discount: _discount,
                          invoiceCurrency: _invoiceCurrency,
                          note: _noteController.text,
                        ),
                      );
                    },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );
  }
}
