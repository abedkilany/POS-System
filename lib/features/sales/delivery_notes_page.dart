import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/delivery_note.dart';
import '../../models/sale.dart';

class DeliveryNotesPage extends StatefulWidget {
  const DeliveryNotesPage({super.key, required this.store});
  final AppStore store;

  @override
  State<DeliveryNotesPage> createState() => _DeliveryNotesPageState();
}

class _DeliveryNotesPageState extends State<DeliveryNotesPage> {
  Future<void> _createFromSale() async {
    final sale = await showDialog<Sale>(
      context: context,
      builder: (context) {
        final sales = widget.store.sales.where((item) => !item.isCancelled && widget.store.deliveryNoteForSale(item.id) == null).toList();
        return AlertDialog(
          title: const Text('Create delivery note'),
          content: SizedBox(
            width: 480,
            child: sales.isEmpty
                ? const Text('No eligible invoices without delivery notes.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: sales.length,
                    itemBuilder: (context, index) {
                      final sale = sales[index];
                      return ListTile(
                        title: Text(sale.invoiceNo),
                        subtitle: Text('${sale.customerName} • ${sale.items.length} items'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(sale),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        );
      },
    );
    if (sale == null) return;
    try {
      await widget.store.createDeliveryNoteFromSale(sale.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery note created')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _markDelivered(DeliveryNote note) async {
    await widget.store.markDeliveryNoteDelivered(note.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery note marked as delivered')));
  }

  Future<void> _delete(DeliveryNote note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete delivery note?'),
        content: Text('Delete ${note.deliveryNo}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) await widget.store.deleteDeliveryNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.store.deliveryNotes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Notes'),
        actions: [IconButton(onPressed: _createFromSale, icon: const Icon(Icons.add), tooltip: 'Create from invoice')],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createFromSale, icon: const Icon(Icons.local_shipping_outlined), label: const Text('Create')),
      body: notes.isEmpty
          ? const Center(child: Text('No delivery notes yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(child: Icon(note.isDelivered ? Icons.check : Icons.local_shipping_outlined)),
                    title: Text(note.deliveryNo),
                    subtitle: Text('${note.customerName} • ${note.invoiceNo} • ${note.status}'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('Date: ${note.date.toLocal().toString().split('.').first}'),
                      ),
                      const SizedBox(height: 8),
                      for (final item in note.items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.productName),
                          trailing: Text('${item.quantity} ${item.unitName}'.trim()),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(onPressed: note.isDelivered ? null : () => _markDelivered(note), icon: const Icon(Icons.done_all), label: const Text('Delivered')),
                          const SizedBox(width: 8),
                          TextButton.icon(onPressed: () => _delete(note), icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
