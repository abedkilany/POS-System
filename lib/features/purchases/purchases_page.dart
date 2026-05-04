import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final purchases = widget.store.purchases;
    final currency = widget.store.storeProfile.currency;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('purchases'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(tr.text('purchases_desc')),
            ],
          );
          final button = FilledButton.icon(
            onPressed: () => _openPurchaseDialog(context),
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(tr.text('new_purchase')),
          );
          return compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), button])
              : Row(children: [Expanded(child: title), button]);
        }),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: tr.text('purchase_total'), value: formatCurrency(widget.store.totalPurchasesAmount, currency: currency), icon: Icons.shopping_cart_checkout),
            _MetricCard(label: tr.text('pending_purchases'), value: '${widget.store.pendingPurchaseCount}', icon: Icons.pending_actions),
            _MetricCard(label: tr.text('received_purchases'), value: '${purchases.where((p) => p.isReceived).length}', icon: Icons.done_all),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: purchases.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Text(tr.text('no_purchases_yet')))
              : Column(
                  children: [
                    for (final purchase in purchases) ...[
                      _PurchaseTile(
                        purchase: purchase,
                        currency: currency,
                        onReceive: purchase.status == 'Draft' ? () => _receivePurchase(context, purchase.id) : null,
                        onCancel: !purchase.isCancelled ? () => _cancelPurchase(context, purchase.id) : null,
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _receivePurchase(BuildContext context, String id) async {
    try {
      await widget.store.receivePurchase(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('purchase_received'))));
      setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelPurchase(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('cancel_purchase')),
        content: Text(AppLocalizations.of(context).text('cancel_purchase_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context).text('confirm'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.cancelPurchase(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('purchase_cancelled'))));
      setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openPurchaseDialog(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final items = <PurchaseItem>[];
    String supplierId = widget.store.suppliers.isNotEmpty ? widget.store.suppliers.first.id : '';
    String supplierName = widget.store.suppliers.isNotEmpty ? widget.store.suppliers.first.name : '';
    Product? selectedProduct = widget.store.products.isNotEmpty ? widget.store.products.first : null;
    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController(text: selectedProduct?.cost.toStringAsFixed(2) ?? '0');
    bool receiveNow = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
          return AlertDialog(
            title: Text(tr.text('new_purchase')),
            content: SizedBox(
              width: 720,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: supplierId.isEmpty ? null : supplierId,
                        decoration: InputDecoration(labelText: tr.text('supplier')),
                        items: widget.store.suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(),
                        onChanged: (value) {
                          final matches = widget.store.suppliers.where((s) => s.id == value).toList();
                          final supplier = matches.isEmpty ? null : matches.first;
                          supplierId = supplier?.id ?? '';
                          supplierName = supplier?.name ?? '';
                        },
                        validator: (_) => supplierId.isEmpty ? tr.text('supplier_required') : null,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              value: selectedProduct?.id,
                              decoration: InputDecoration(labelText: tr.text('product')),
                              items: widget.store.products.map((product) => DropdownMenuItem(value: product.id, child: Text(product.name))).toList(),
                              onChanged: (value) {
                                final matches = widget.store.products.where((p) => p.id == value).toList();
                                selectedProduct = matches.isEmpty ? null : matches.first;
                                costController.text = selectedProduct?.cost.toStringAsFixed(2) ?? '0';
                                setDialogState(() {});
                              },
                            ),
                          ),
                          SizedBox(width: 110, child: TextFormField(controller: qtyController, decoration: InputDecoration(labelText: tr.text('quantity')), keyboardType: TextInputType.number)),
                          SizedBox(width: 130, child: TextFormField(controller: costController, decoration: InputDecoration(labelText: tr.text('unit_cost')), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                          OutlinedButton.icon(
                            onPressed: selectedProduct == null
                                ? null
                                : () {
                                    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                                    final cost = double.tryParse(costController.text.trim()) ?? -1;
                                    if (qty <= 0 || cost < 0) return;
                                    final product = selectedProduct!;
                                    items.add(PurchaseItem(productId: product.id, productName: product.name, quantity: qty, unitCost: cost));
                                    setDialogState(() {});
                                  },
                            icon: const Icon(Icons.add),
                            label: Text(tr.text('add_item')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty) Text(tr.text('no_items_added')) else ...items.map((item) => ListTile(
                            dense: true,
                            title: Text(item.productName),
                            subtitle: Text('${item.quantity} × ${formatCurrency(item.unitCost, currency: widget.store.storeProfile.currency)}'),
                            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setDialogState(() => items.remove(item))),
                          )),
                      const Divider(),
                      SwitchListTile(
                        value: receiveNow,
                        onChanged: (value) => setDialogState(() => receiveNow = value),
                        title: Text(tr.text('receive_now')),
                        subtitle: Text(tr.text('receive_now_desc')),
                      ),
                      Text('${tr.text('total')}: ${formatCurrency(total, currency: widget.store.storeProfile.currency)}', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false) || items.isEmpty) return;
                  try {
                    await widget.store.createPurchase(supplierId: supplierId, supplierName: supplierName, items: List.of(items), receiveNow: receiveNow);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) setState(() {});
                  } catch (error) {
                    if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                child: Text(tr.text('save')),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [Icon(icon), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: Theme.of(context).textTheme.titleLarge)]))]),
          ),
        ),
      );
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase, required this.currency, this.onReceive, this.onCancel});
  final Purchase purchase;
  final String currency;
  final VoidCallback? onReceive, onCancel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Icon(purchase.isReceived ? Icons.inventory : purchase.isCancelled ? Icons.cancel_outlined : Icons.pending_actions)),
      title: Text('${purchase.purchaseNo} • ${purchase.supplierName}'),
      subtitle: Text('${purchase.status} • ${purchase.totalUnits} units • ${purchase.date.toLocal().toString().split('.').first}'),
      trailing: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(formatCurrency(purchase.subtotal, currency: currency)),
          if (onReceive != null) IconButton(tooltip: AppLocalizations.of(context).text('receive'), onPressed: onReceive, icon: const Icon(Icons.download_done)),
          if (onCancel != null) IconButton(tooltip: AppLocalizations.of(context).text('cancel'), onPressed: onCancel, icon: const Icon(Icons.cancel_outlined)),
        ],
      ),
    );
  }
}
