import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/inventory_batch.dart';
import '../../models/product.dart';

class _BatchDraft {
  final quantity = TextEditingController();
  final number = TextEditingController();
  DateTime? expirationDate;

  void dispose() {
    quantity.dispose();
    number.dispose();
  }
}

Future<List<BatchAllocation>?> showBatchAllocationDialog(
  BuildContext context, {
  required Product product,
  required double expectedQuantity,
  required String sourceId,
  AppLocalizations? localizations,
}) async {
  final drafts = <_BatchDraft>[
    _BatchDraft()..quantity.text = '$expectedQuantity'
  ];
  final result = await showDialog<List<BatchAllocation>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final tr = localizations ?? AppLocalizations.of(context);
        final allocated = drafts.fold<double>(
          0,
          (sum, draft) =>
              sum + (double.tryParse(draft.quantity.text.trim()) ?? 0),
        );
        return AlertDialog(
          title: Text('${tr.text('expiry_batches')} — ${product.name}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tr.text('quantity')}: $expectedQuantity'),
                  const SizedBox(height: 12),
                  for (var index = 0; index < drafts.length; index += 1)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextField(
                              controller: drafts[index].quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: tr.text('quantity')),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: drafts[index].number,
                              decoration: InputDecoration(
                                  labelText: tr.text('batch_number')),
                            ),
                            const SizedBox(height: 8),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(drafts[index].expirationDate == null
                                  ? tr.text('expiration_date')
                                  : MaterialLocalizations.of(context)
                                      .formatMediumDate(
                                          drafts[index].expirationDate!)),
                              trailing:
                                  const Icon(Icons.calendar_month_outlined),
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: drafts[index].expirationDate ??
                                      DateTime.now().add(Duration(
                                          days: product.defaultShelfLifeDays > 0
                                              ? product.defaultShelfLifeDays
                                              : 30)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 36500)),
                                );
                                if (date != null) {
                                  setState(() =>
                                      drafts[index].expirationDate = date);
                                }
                              },
                            ),
                            if (drafts.length > 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: tr.text('delete'),
                                  onPressed: () => setState(() {
                                    drafts.removeAt(index).dispose();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => drafts.add(_BatchDraft())),
                      icon: const Icon(Icons.add),
                      label: Text(tr.text('add_batch')),
                    ),
                  ),
                  Text(
                      '${tr.text('quantity')}: $allocated / $expectedQuantity'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if ((allocated - expectedQuantity).abs() > .000001) return;
                if (drafts.any((draft) =>
                    (double.tryParse(draft.quantity.text.trim()) ?? 0) <= 0 ||
                    (product.expiryEntryRequired &&
                        draft.expirationDate == null))) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  <BatchAllocation>[
                    for (var index = 0; index < drafts.length; index += 1)
                      BatchAllocation(
                        batchId: '$sourceId-batch-$index',
                        quantity:
                            double.parse(drafts[index].quantity.text.trim()),
                        supplierBatchNumber: drafts[index].number.text.trim(),
                        expirationDate: drafts[index].expirationDate,
                      ),
                  ],
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    ),
  );
  for (final draft in drafts) {
    draft.dispose();
  }
  return result;
}
