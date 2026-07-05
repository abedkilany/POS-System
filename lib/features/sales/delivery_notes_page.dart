import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/business_revision_service.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/local_database_service.dart';
import '../../core/storage/sqlite/business_sqlite_store.dart' show BusinessQueryPage;
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
  Future<_DeliveryNotesQueryResult?>? _notesFuture;
  String _notesFutureKey = '';
  Future<BusinessQueryPage<Sale>?>? _eligibleSalesFuture;
  String _eligibleSalesFutureKey = '';

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

  Future<_DeliveryNotesQueryResult?> _queryDeliveryNotesFromSqlite() async {
    final key =
        '${BusinessRevisionService.instance.deliveryNotesRevision}|delivery_notes';
    if (_notesFuture == null || _notesFutureKey != key) {
      _notesFutureKey = key;
      _notesFuture = () async {
        final page = await SaleRepository.queryDeliveryNotesPage(limit: 500);
        if (page == null) return null;
        return _DeliveryNotesQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _notesFuture!;
  }

  Future<BusinessQueryPage<Sale>?> _queryEligibleSalesFromSqlite() {
    final key =
        '${BusinessRevisionService.instance.salesRevision}|eligible_delivery_sales';
    if (_eligibleSalesFuture == null || _eligibleSalesFutureKey != key) {
      _eligibleSalesFutureKey = key;
      _eligibleSalesFuture =
          SaleRepository.queryPage(limit: 500, status: 'all');
    }
    return _eligibleSalesFuture!;
  }

  Future<void> _createFromSale() async {
    final tr = AppLocalizations.of(context);
    final page = await _queryEligibleSalesFromSqlite();
    final eligibleSales = <Sale>[];
    if (page != null) {
      for (final sale in page.items) {
        if (sale.isCancelled) continue;
        final existing = await SaleRepository.getDeliveryNoteBySaleId(sale.id);
        if (existing != null) continue;
        eligibleSales.add(sale);
      }
    }
    if (!mounted) return;

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
                          '${sale.customerName} â€¢ ${_itemsCountLabel(tr, sale.items.length)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(sale),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr.text('close')),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (sale == null) return;
    try {
      await SaleRepository.createDeliveryNoteFromSale(widget.store, sale.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('delivery_note_created'))),
        );
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
    await SaleRepository.markDeliveryNoteDelivered(widget.store, note.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('delivery_note_delivered'))),
      );
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
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await SaleRepository.deleteDeliveryNote(widget.store, note.id);
    }
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

    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return Scaffold(
        appBar: AppBar(title: Text(tr.text('delivery_notes'))),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return FutureBuilder<_DeliveryNotesQueryResult?>(
      future: _queryDeliveryNotesFromSqlite(),
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || result == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(tr.text('delivery_notes')),
            ),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(tr.text('delivery_notes')),
            actions: [
              if (canCreate)
                IconButton(
                  onPressed: _createFromSale,
                  icon: const Icon(Icons.add),
                  tooltip: tr.text('create_delivery_note'),
                ),
            ],
          ),
          floatingActionButton: canCreate
              ? FloatingActionButton.extended(
                  onPressed: _createFromSale,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(tr.text('create_delivery_note')),
                )
              : null,
          body: result.items.isEmpty
              ? Center(child: Text(tr.text('no_delivery_notes')))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: result.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final note = result.items[index];
                    return Card(
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          child: Icon(note.isDelivered
                              ? Icons.check
                              : Icons.local_shipping_outlined),
                        ),
                        title: Text(note.deliveryNo),
                        subtitle: Text(
                          '${note.customerName} â€¢ ${note.invoiceNo} â€¢ ${_statusLabel(tr, note.status)}',
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${tr.text('date')}: ${note.date.toLocal().toString().split('.').first}',
                            ),
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
                              if (canCreate && canDelete)
                                const SizedBox(width: 8),
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
      },
    );
  }
}

class _DeliveryNotesQueryResult {
  const _DeliveryNotesQueryResult({
    required this.items,
    required this.totalCount,
  });

  final List<DeliveryNote> items;
  final int totalCount;
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
