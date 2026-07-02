import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/delivery_note.dart';
import '../../models/sale.dart';
import '../../models/user_role.dart';

class DeliveryNotesPage extends StatefulWidget {
  const DeliveryNotesPage({super.key, required this.store});
  final AppStore store;

  @override
  State<DeliveryNotesPage> createState() => _DeliveryNotesPageState();
}

class _DeliveryNotesPageState extends State<DeliveryNotesPage> {
  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    widget.store.ensureDeliveryNotesPageDataLoaded();
  }

  @override
  void didUpdateWidget(covariant DeliveryNotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      widget.store.ensureDeliveryNotesPageDataLoaded();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  String _statusLabel(AppLocalizations tr, String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return tr.text('delivered');
      case 'pending':
        return tr.text('connection_state_pending');
      case 'cancelled':
      case 'canceled':
        return tr.text('cancelled');
      default:
        return status;
    }
  }

  String _itemsCountLabel(AppLocalizations tr, int count) =>
      '$count ${tr.text('items')}';

  Future<void> _createFromSale() async {
    final tr = AppLocalizations.of(context);
    final eligibleSales = widget.store.sales
        .where(
          (item) =>
              !item.isCancelled &&
              widget.store.deliveryNoteForSale(item.id) == null,
        )
        .toList(growable: false);
    final sale = await showDialog<Sale>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr.text('create_delivery_note')),
          content: SizedBox(
            width: 480,
            child: eligibleSales.isEmpty
                ? Text(tr.text('no_eligible_delivery'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: eligibleSales.length,
                    itemBuilder: (context, index) {
                      final sale = eligibleSales[index];
                      return ListTile(
                        title: Text(sale.invoiceNo),
                        subtitle: Text(
                            '${sale.customerName} • ${_itemsCountLabel(tr, sale.items.length)}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(sale),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr.text('close')))
          ],
        );
      },
    );
    if (sale == null) {
      return;
    }
    try {
      await widget.store.createDeliveryNoteFromSale(sale.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('delivery_note_created'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _markDelivered(DeliveryNote note) async {
    final tr = AppLocalizations.of(context);
    await widget.store.markDeliveryNoteDelivered(note.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('delivery_note_delivered'))));
    }
  }

  Future<void> _delete(DeliveryNote note) async {
    final tr = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete_delivery_note')),
        content: Text(tr.format(
            'delete_delivery_note_question', {'deliveryNo': note.deliveryNo})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirm == true) await widget.store.deleteDeliveryNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canCreate = widget.store.hasAnyPermission(<String>{
      AppPermission.deliveryNotesManage,
      AppPermission.salesCreate,
    });
    final canDelete = widget.store.hasAnyPermission(<String>{
      AppPermission.deliveryNotesManage,
      AppPermission.salesCancel,
    });
    final canAccess = canCreate || canDelete;
    if (!canAccess) {
      return _AccessDeniedScaffold(
        title: tr.text('delivery_notes'),
        message: 'This section is not available for your current role.',
      );
    }
    final notes = widget.store.deliveryNotes;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('delivery_notes')),
        actions: [
          if (canCreate)
            IconButton(
              onPressed: _createFromSale,
              icon: const Icon(Icons.add),
              tooltip: tr.text('create_delivery_note'),
            )
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _createFromSale,
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(tr.text('create_delivery_note')),
            )
          : null,
      body: notes.isEmpty
          ? Center(child: Text(tr.text('no_delivery_notes')))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(
                        child: Icon(note.isDelivered
                            ? Icons.check
                            : Icons.local_shipping_outlined)),
                    title: Text(note.deliveryNo),
                    subtitle: Text(
                        '${note.customerName} • ${note.invoiceNo} • ${_statusLabel(tr, note.status)}'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                            '${tr.text('date')}: ${note.date.toLocal().toString().split('.').first}'),
                      ),
                      const SizedBox(height: 8),
                      for (final item in note.items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.productName),
                          trailing:
                              Text('${item.quantity} ${item.unitName}'.trim()),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (canCreate)
                            TextButton.icon(
                              onPressed: note.isDelivered
                                  ? null
                                  : () => _markDelivered(note),
                              icon: const Icon(Icons.done_all),
                              label: Text(tr.text('delivered')),
                            ),
                          if (canCreate && canDelete) const SizedBox(width: 8),
                          if (canDelete)
                            TextButton.icon(
                              onPressed: () => _delete(note),
                              icon: const Icon(Icons.delete_outline),
                              label: Text(tr.text('delete')),
                            ),
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

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  const Text(
                    'No access to this section.',
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
