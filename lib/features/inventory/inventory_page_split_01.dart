part of 'inventory_page.dart';

String _batchStatusLabel(AppLocalizations tr, String status) {
  if (status != 'depleted') return tr.text(status);
  switch (tr.locale.languageCode) {
    case 'ar':
      return 'نافدة';
    case 'fr':
      return 'Épuisé';
    default:
      return 'Depleted';
  }
}

String _movementTypeLabel(AppLocalizations tr, String type) {
  switch (type) {
    case 'auto_correction':
      return tr.text('auto_correction');
    case 'purchase_receive':
      return tr.text('purchase_received');
    case 'purchase_return':
      return tr.text('purchase_return');
    case 'purchase_cancel':
      return tr.text('purchase_cancel');
    case 'sale':
      return tr.text('sale_invoice');
    case 'sale_return':
      return tr.text('return_sale');
    case 'sale_restore':
      return tr.text('sale_restore');
    case 'sale_cancel':
      return tr.text('sale_cancel');
    case 'paymentReceived':
      return tr.text('payment_received');
    case 'paymentPaid':
      return tr.text('payment_paid');
    case 'paymentReversal':
      return tr.text('payment_reversal');
    case 'transfer_in':
    case 'warehouse_transfer_in':
      return tr.text('warehouse_transfer_in');
    case 'transfer_out':
    case 'warehouse_transfer_out':
      return tr.text('warehouse_transfer_out');
    case 'count_adjustment':
      return tr.text('count_adjustment');
    case 'manufacturing_consume':
      return tr.text('manufacturing_consume');
    case 'manufacturing_produce':
      return tr.text('manufacturing_output');
    case 'manufacturing_output':
      return tr.text('manufacturing_output');
    default:
      return type.replaceAll('_', ' ');
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});

  final ApplicationSession store;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryOverviewMetrics {
  const _InventoryOverviewMetrics({
    required this.productCount,
    required this.totalUnits,
    required this.lowStockCount,
    required this.inventoryRetailValue,
    required this.pendingAutoCorrectionCount,
  });

  final int productCount;
  final double totalUnits;
  final int lowStockCount;
  final double inventoryRetailValue;
  final int pendingAutoCorrectionCount;

  factory _InventoryOverviewMetrics.fromStore(ApplicationSession store) {
    final products = store.catalog.stockTrackedProducts;
    var totalUnits = 0.0;
    var lowStockCount = 0;
    var inventoryRetailValue = 0.0;
    for (final product in products) {
      totalUnits += product.stock;
      inventoryRetailValue += product.usdPrice * product.stock;
      if (product.stock <= product.lowStockThreshold) {
        lowStockCount += 1;
      }
    }
    return _InventoryOverviewMetrics(
      productCount: store.catalog.products.length,
      totalUnits: totalUnits,
      lowStockCount: lowStockCount,
      inventoryRetailValue: inventoryRetailValue,
      pendingAutoCorrectionCount:
          store.inventory.pendingAutoCorrectionMovements.length,
    );
  }
}

class _InventoryBatchesTab extends StatefulWidget {
  const _InventoryBatchesTab({required this.store});

  final ApplicationSession store;

  @override
  State<_InventoryBatchesTab> createState() => _InventoryBatchesTabState();
}

class _InventoryBatchesTabState extends State<_InventoryBatchesTab> {
  String query = '';
  String status = 'all';

  Future<void> _changeStatus(Map<String, dynamic> row, String value) async {
    await widget.store.inventory
        .setExpiryBatchStatus(row['batchId'].toString(), value);
    if (mounted) setState(() {});
  }

  Future<void> _adjustBatch(
    Map<String, dynamic> row, {
    required bool dispose,
  }) async {
    final controller = TextEditingController(
      text: dispose ? (row['quantity'] as num? ?? 0).toString() : '',
    );
    final tr = AppLocalizations.of(context);
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(dispose ? tr.text('dispose_batch') : tr.text('batch_count')),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr.text('quantity')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 0) return;
    final current = (row['quantity'] as num? ?? 0).toDouble();
    final delta = dispose ? -value : value - current;
    if (delta == 0) return;
    await widget.store.inventory.adjustExpiryBatchStock(
      productId: row['productId'].toString(),
      warehouseId: row['warehouseId'].toString(),
      batchId: row['batchId'].toString(),
      quantityDelta: delta,
      reason: dispose ? 'Expired batch disposal' : 'Batch stock count',
      adjustmentCategory: dispose ? 'expired' : 'stock_count_adjustment',
    );
    if (dispose && value >= current) {
      await widget.store.inventory
          .setExpiryBatchStatus(row['batchId'].toString(), 'disposed');
    }
    if (mounted) setState(() {});
  }

  Future<void> _reverseLatestBatchAdjustment(Map<String, dynamic> row) async {
    final tr = AppLocalizations.of(context);
    final batchId = row['batchId']?.toString() ?? '';
    final candidates = widget.store.inventory.stockMovements
        .where((movement) =>
            movement.batchId == batchId &&
            movement.reversalOfMovementId.isEmpty &&
            (movement.type == 'inventory_loss' ||
                movement.type == 'count_adjustment'))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (candidates.isEmpty) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(tr.text('reverse_batch_adjustment')),
          content: TextField(
              controller: controller,
              decoration: InputDecoration(labelText: tr.text('reason'))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text(tr.text('reverse'))),
          ],
        );
      },
    );
    if (reason == null) return;
    await widget.store.inventory.reverseExpiryBatchAdjustment(candidates.first.id, reason: reason);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return FutureBuilder<List<Map<String, dynamic>>?>(
      future: LocalDatabaseService.getInventoryBatchReportFromSqlite(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final normalizedQuery = query.trim().toLowerCase();
        final canManageCorrections = widget.store.security.hasPermission(
          AppPermission.inventoryCorrectionsManage,
        );
        final canExport = widget.store.security.hasPermission(
          AppPermission.reportsExport,
        );
        final rows = allRows.where((row) {
          final rowStatus = row['status']?.toString() ?? 'active';
          if (status != 'all' && rowStatus != status) return false;
          if (normalizedQuery.isEmpty) return true;
          return '${row['productName']} ${row['supplierBatchNumber']} ${row['warehouseId']} ${row['sourceType']} ${row['sourceId']}'
              .toLowerCase()
              .contains(normalizedQuery);
        }).toList();
        if (allRows.isEmpty) {
          return Center(child: Text(tr.text('no_inventory_items')));
        }
        final today = DateTime.now();
        final startOfToday = DateTime(today.year, today.month, today.day);
        final expiredCount = allRows.where((row) {
          if ((row['quantity'] as num? ?? 0).toDouble() <= 0.000001) {
            return false;
          }
          final expiry =
              DateTime.tryParse(row['expirationDate']?.toString() ?? '');
          return expiry != null && expiry.isBefore(startOfToday);
        }).length;
        final expiringSoonCount = allRows.where((row) {
          if ((row['quantity'] as num? ?? 0).toDouble() <= 0.000001) {
            return false;
          }
          final expiry =
              DateTime.tryParse(row['expirationDate']?.toString() ?? '');
          if (expiry == null || expiry.isBefore(startOfToday)) return false;
          final alertDays = (row['alertDays'] as num? ?? 30).toInt();
          return expiry.difference(startOfToday).inDays <= alertDays;
        }).length;
        final atRiskValue = allRows.fold<double>(0, (sum, row) {
          final quantity = (row['quantity'] as num? ?? 0).toDouble();
          if (quantity <= 0.000001) return sum;
          final expiry =
              DateTime.tryParse(row['expirationDate']?.toString() ?? '');
          if (expiry == null) return sum;
          final alertDays = (row['alertDays'] as num? ?? 30).toInt();
          if (expiry.difference(startOfToday).inDays > alertDays) return sum;
          return sum + quantity * (row['unitCost'] as num? ?? 0).toDouble();
        });
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(spacing: 12, runSpacing: 8, children: [
              Chip(
                  avatar: const Icon(Icons.inventory_2_outlined),
                  label:
                      Text('${tr.text('unified_batch')}: ${allRows.length}')),
              Chip(
                  avatar: const Icon(Icons.error_outline, color: Colors.red),
                  label: Text('${tr.text('expired')}: $expiredCount')),
              Chip(
                  avatar: const Icon(Icons.notification_important_outlined,
                      color: Colors.orange),
                  label:
                      Text('${tr.text('expiring_soon')}: $expiringSoonCount')),
              Chip(
                  avatar: const Icon(Icons.payments_outlined),
                  label: Text(
                      '${tr.text('estimated_value')}: ${formatUsdReferenceAmount(atRiskValue, widget.store.runtime.profile)}')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: tr.text('search')),
                onChanged: (value) => setState(() => query = value),
              )),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: status,
                items: <String>[
                  'all',
                  'active',
                  'blocked',
                  'depleted',
                  'disposed'
                ]
                    .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(_batchStatusLabel(tr, value))))
                    .toList(),
                onChanged: (value) => setState(() => status = value ?? 'all'),
              ),
              IconButton(
                tooltip: tr.text('export_csv'),
                icon: const Icon(Icons.download_outlined),
                onPressed: rows.isEmpty || !canExport
                    ? null
                    : () async {
                        try {
                          await SqlResultExportService.exportRows(
                            rows: rows
                                .map((row) => Map<String, Object?>.from(row))
                                .toList(),
                            format: 'csv',
                            baseFileName: 'ventio-inventory-batches',
                          );
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(localizedErrorText(
                                    AppLocalizations.of(context), error)),
                              ),
                            );
                          }
                        }
                      },
              ),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(tr.text('no_inventory_items')))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final expiry = DateTime.tryParse(
                          row['expirationDate']?.toString() ?? '');
                      final days = expiry == null
                          ? null
                          : DateTime(expiry.year, expiry.month, expiry.day)
                              .difference(startOfToday)
                              .inDays;
                      final color = days == null
                          ? Colors.grey
                          : days < 0
                              ? Colors.red
                              : days <= 30
                                  ? Colors.orange
                                  : Colors.green;
                      final quantity =
                          (row['quantity'] as num? ?? 0).toDouble();
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: .14),
                            child: Icon(
                              expiry == null
                                  ? Icons.inventory_2_outlined
                                  : Icons.event_outlined,
                              color: color,
                            ),
                          ),
                          title: Text(row['productName']?.toString() ?? ''),
                          subtitle: Text([
                            if ((row['supplierBatchNumber']?.toString() ?? '')
                                .isNotEmpty)
                              '${tr.text('batch_number')}: ${row['supplierBatchNumber']}',
                            '${tr.text('warehouse')}: ${row['warehouseId']}',
                            '${tr.text('quantity')}: ${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)}',
                            '${tr.text('status')}: ${_batchStatusLabel(tr, row['status']?.toString() ?? 'active')}',
                            if ((row['sourceType']?.toString() ?? '')
                                .isNotEmpty)
                              row['sourceType'].toString().replaceAll('_', ' '),
                            if (DateTime.tryParse(
                                    row['receivedAt']?.toString() ?? '') !=
                                null)
                              '${tr.text('received')}: ${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(row['receivedAt'].toString()).toLocal())}',
                          ].join(' • ')),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    expiry == null
                                        ? tr.text('no_expiration_date')
                                        : MaterialLocalizations.of(context)
                                            .formatMediumDate(expiry),
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  if (days != null)
                                    Text(days < 0
                                        ? tr.text('expired')
                                        : '$days ${tr.text('days')}'),
                                ]),
                            PopupMenuButton<String>(
                              enabled: canManageCorrections,
                              onSelected: (value) async {
                                if (value == 'count') {
                                  await _adjustBatch(row, dispose: false);
                                }
                                if (value == 'dispose') {
                                  await _adjustBatch(row, dispose: true);
                                }
                                if (value == 'block') {
                                  await _changeStatus(row, 'blocked');
                                }
                                if (value == 'activate') {
                                  await _changeStatus(row, 'active');
                                }
                                if (value == 'reverse') {
                                  await _reverseLatestBatchAdjustment(row);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'count',
                                    child: Text(tr.text('batch_count'))),
                                if (expiry != null)
                                  PopupMenuItem(
                                      value: 'dispose',
                                      child: Text(tr.text('dispose_batch'))),
                                PopupMenuItem(
                                    value: 'reverse',
                                    child: Text(tr.text('reverse_adjustment'))),
                                if ((row['status']?.toString() ?? 'active') ==
                                    'blocked')
                                  PopupMenuItem(
                                      value: 'activate',
                                      child: Text(tr.text('activate_batch')))
                                else
                                  PopupMenuItem(
                                      value: 'block',
                                      child: Text(tr.text('block_batch'))),
                              ],
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
