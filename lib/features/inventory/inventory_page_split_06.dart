part of 'inventory_page.dart';

class _StockCountProductTile extends StatelessWidget {
  const _StockCountProductTile(
      {required this.store,
      required this.product,
      required this.line,
      required this.movementsAfter});

  final ApplicationSession store;
  final Product product;
  final InventoryCountLine? line;
  final int movementsAfter;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return ListTile(
      title: Text(product.name),
      subtitle: Text([
        '${tr.text('system_stock')}: ${line?.snapshotStock ?? product.stock}',
        if (line?.isCounted == true)
          '${tr.text('counted')}: ${line!.countedQty}',
        if (line?.countedAt != null)
          '${tr.text('counted_at')}: ${line!.countedAt!.toLocal().toString().split('.').first}',
        if (movementsAfter > 0)
          '⚠ ${tr.text('movements_after_count')}: $movementsAfter',
      ].join(' • ')),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 8,
        children: [
          if (line?.isCounted == true)
            OutlinedButton.icon(
              onPressed: () => _resetCount(context),
              icon: const Icon(Icons.restart_alt_outlined),
              label: Text(tr.text('reset_count')),
            ),
          FilledButton(
            onPressed: () => _enterCount(context),
            child: Text(line?.isCounted == true
                ? tr.text('recount')
                : tr.text('count')),
          ),
        ],
      ),
    );
  }

  Future<void> _resetCount(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('reset_count')),
        content: Text(tr.text('reset_count_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('reset_count')),
          ),
        ],
      ),
    );
    if (shouldReset != true) return;
    try {
      final activeSessionId = store.inventory.activeInventoryCountSession?.id;
      if (activeSessionId == null) return;
      await store.inventory.resetInventoryCountLine(
        sessionId: activeSessionId,
        productId: product.id,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }

  Future<void> _enterCount(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr.text('count')} • ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: tr.text('actual_quantity')),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    if (value == null) return;
    try {
      final activeSessionId = store.inventory.activeInventoryCountSession?.id;
      if (activeSessionId == null) return;
      await store.inventory.countInventoryLine(
          sessionId: activeSessionId, productId: product.id, countedQty: value);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }
}

Future<void> _openWasteLossDialog(BuildContext context, ApplicationSession store) async {
  final tr = AppLocalizations.of(context);
  final products = store.catalog.stockTrackedProducts;
  final warehouses = store.inventory.warehouses;
  if (products.isEmpty || warehouses.isEmpty) return;
  final quantityController = TextEditingController();
  final notesController = TextEditingController();
  var productId = products.first.id;
  var warehouseId = store.inventory.resolveWarehouseForPurchase().id;
  var category = 'damage';
  final categories = <String, String>{
    'damage': tr.text('adjustment_damage'),
    'expired': tr.text('adjustment_expired'),
    'free_sample': tr.text('adjustment_free_sample'),
    'internal_consumption': tr.text('adjustment_internal_consumption'),
    'other': tr.text('adjustment_other'),
  };
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(tr.text('record_waste_loss')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: productId,
                decoration: InputDecoration(labelText: tr.text('product')),
                items: products
                    .map((product) => DropdownMenuItem<String>(
                          value: product.id,
                          child: Text(product.name),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  productId = value ?? productId;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: warehouseId,
                decoration: InputDecoration(labelText: tr.text('warehouse')),
                items: warehouses
                    .map((warehouse) => DropdownMenuItem<String>(
                          value: warehouse.id,
                          child: Text(warehouse.name),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  warehouseId = value ?? warehouseId;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: InputDecoration(
                  labelText: tr.text('adjustment_reason_type'),
                ),
                items: categories.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  category = value ?? category;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                decoration: InputDecoration(
                  labelText: tr.text('waste_quantity'),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: tr.text('notes_optional'),
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final quantity =
                  double.tryParse(quantityController.text.trim()) ?? 0;
              if (quantity <= 0) return;
              try {
                await store.inventory.recordWasteLoss(
                  productId: productId,
                  warehouseId: warehouseId,
                  quantity: quantity,
                  reason: categories[category] ?? category,
                  adjustmentCategory: category,
                  notes: notesController.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(localizedErrorText(
                        AppLocalizations.of(dialogContext),
                        error,
                      )),
                    ),
                  );
                }
              }
            },
            child: Text(tr.text('save')),
          ),
        ],
      ),
    ),
  );
  quantityController.dispose();
  notesController.dispose();
}

bool _hasWasteReversal(ApplicationSession store, StockMovement movement) {
  return store.inventory.stockMovements.any(
    (item) => item.reversalOfMovementId == movement.id,
  );
}

Future<void> _showWasteLossDetails(
  BuildContext context,
  ApplicationSession store,
  StockMovement movement, {
  required bool canManageWaste,
  required Future<void> Function(StockMovement movement) onDelete,
}) async {
  final tr = AppLocalizations.of(context);
  final reversed = _hasWasteReversal(store, movement);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(movement.productName),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _wasteDetailRow(tr.text('waste_detail_quantity'),
                movement.quantity.abs().toString()),
            _wasteDetailRow(tr.text('waste_detail_value'),
                formatUsdReferenceAmount(movement.value, store.runtime.profile)),
            _wasteDetailRow(tr.text('waste_detail_reason'),
                _adjustmentCategoryLabel(tr, movement.adjustmentCategory)),
            _wasteDetailRow(
                tr.text('waste_detail_warehouse'), movement.warehouseName),
            _wasteDetailRow(tr.text('waste_detail_date'),
                movement.date.toLocal().toString().substring(0, 16)),
            if (movement.notes.trim().isNotEmpty)
              _wasteDetailRow(tr.text('waste_detail_notes'), movement.notes),
            if (reversed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr.text('waste_already_reversed'),
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (canManageWaste && !reversed)
          TextButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: Text(tr.text('delete_waste_loss')),
                  content: Text(tr.text('delete_waste_loss_confirmation')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, false),
                      child: Text(tr.text('cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(confirmContext, true),
                      child: Text(tr.text('confirm_delete')),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await onDelete(movement);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(localizedErrorText(
                          AppLocalizations.of(dialogContext), error)),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(tr.text('delete_waste_loss')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr.text('close')),
        ),
      ],
    ),
  );
}

Widget _wasteDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _WasteLossReportDb extends StatefulWidget {
  const _WasteLossReportDb({
    required this.store,
    required this.canManageWaste,
  });
  final ApplicationSession store;
  final bool canManageWaste;

  @override
  State<_WasteLossReportDb> createState() => _WasteLossReportDbState();
}

class _WasteLossReportDbState extends State<_WasteLossReportDb> {
  Future<_StockMovementsQueryResult?>? _future;
  String _futureKey = '';
  int _visibleCount = 100;

  Future<_StockMovementsQueryResult?> _queryWasteLossFromSqlite() {
    final limit = _visibleCount.clamp(1, 500).toInt();
    final key = '${widget.store.inventory.revision}|$limit';
    if (_future == null || _futureKey != key) {
      _futureKey = key;
      _future = () async {
        final page = await LocalDatabaseService.queryWasteLossFromSqlite(
          limit: limit,
        );
        if (page == null) return null;
        return _StockMovementsQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _future!;
  }

  void _loadMore(int totalCount) {
    setState(() {
      _visibleCount = math.min(totalCount, _visibleCount + 100);
      _future = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
    })) {
      return _InventorySectionDenied(
        title: tr.text('waste_loss_report'),
        message: tr.text('waste_loss_reporting_no_access'),
      );
    }
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return _WasteLossReport(
        store: widget.store,
        canManageWaste: widget.canManageWaste,
      );
    }
    return FutureBuilder<_StockMovementsQueryResult?>(
      future: _queryWasteLossFromSqlite(),
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (result == null || snapshot.hasError) {
          return _WasteLossReport(
            store: widget.store,
            canManageWaste: widget.canManageWaste,
          );
        }
        return _WasteLossReportView(
          store: widget.store,
          movements: result.items,
          totalCount: result.totalCount,
          canManageWaste: widget.canManageWaste,
          onDelete: (movement) async {
            await widget.store.inventory.deleteWasteLoss(movement.id);
            if (mounted) {
              setState(() {
                _future = null;
              });
            }
          },
          onLoadMore:
              result.hasMore ? () => _loadMore(result.totalCount) : null,
        );
      },
    );
  }
}

class _WasteLossReportView extends StatelessWidget {
  const _WasteLossReportView({
    required this.store,
    required this.movements,
    required this.totalCount,
    required this.canManageWaste,
    required this.onDelete,
    this.onLoadMore,
  });

  final ApplicationSession store;
  final List<StockMovement> movements;
  final int totalCount;
  final bool canManageWaste;
  final Future<void> Function(StockMovement movement) onDelete;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final activeMovements = movements
        .where((movement) => !_hasWasteReversal(store, movement))
        .toList(growable: false);
    final totals = <String, _WasteTotal>{};
    double totalValue = 0;
    double totalQty = 0;
    for (final movement in activeMovements) {
      final key = movement.adjustmentCategory.isEmpty
          ? 'other'
          : movement.adjustmentCategory;
      final current = totals[key] ?? _WasteTotal();
      current.quantity += movement.quantity.abs();
      current.value += movement.value;
      current.count += 1;
      totals[key] = current;
      totalValue += movement.value;
      totalQty += movement.quantity.abs();
    }
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        if (canManageWaste)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () => _openWasteLossDialog(context, store),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(tr.text('record_waste_loss')),
            ),
          ),
        if (canManageWaste) const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('loss_movements'),
                value: '${activeMovements.length}',
                icon: Icons.report_problem_outlined),
            SummaryCard(
                title: tr.text('loss_quantity'),
                value: totalQty.toStringAsFixed(
                    totalQty.truncateToDouble() == totalQty ? 0 : 2),
                icon: Icons.remove_circle_outline),
            SummaryCard(
                title: tr.text('loss_value'),
                value: formatUsdReferenceAmount(totalValue, store.runtime.profile),
                icon: Icons.money_off_outlined),
          ],
        ),
        const SizedBox(height: 20),
        PageDataLoadIndicator(
          loadedCount: movements.length,
          totalCount: totalCount,
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  tr.text('waste_loss_records'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              if (movements.isEmpty)
                Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(tr.text('no_waste_loss_records')),
                )
              else
                for (final movement in movements) ...[
                  ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        _hasWasteReversal(store, movement)
                            ? Icons.undo_outlined
                            : Icons.delete_sweep_outlined,
                      ),
                    ),
                    title: Text(movement.productName),
                    subtitle: Text(
                      '${_adjustmentCategoryLabel(tr, movement.adjustmentCategory)} • '
                      '${tr.text('quantity')}: ${movement.quantity.abs()} • '
                      '${movement.date.toLocal().toString().substring(0, 16)}',
                    ),
                    trailing: Text(formatUsdReferenceAmount(
                        movement.value, store.runtime.profile)),
                    onTap: () => _showWasteLossDetails(
                      context,
                      store,
                      movement,
                      canManageWaste:
                          canManageWaste && movement.type == 'inventory_loss',
                      onDelete: onDelete,
                    ),
                  ),
                  const Divider(height: 1),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: totals.isEmpty
              ? Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(tr.text('no_waste_loss_records')))
              : Column(
                  children: [
                    ListTile(
                        title: Text(tr.text('waste_loss_by_reason'),
                            style: Theme.of(context).textTheme.titleMedium)),
                    const Divider(height: 1),
                    for (final entry in totals.entries) ...[
                      ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.category_outlined)),
                        title: Text(_adjustmentCategoryLabel(tr, entry.key)),
                        subtitle: Text(
                            '${tr.text('movements')}: ${entry.value.count} • ${tr.text('quantity')}: ${entry.value.quantity}'),
                        trailing: Text(formatUsdReferenceAmount(
                            entry.value.value, store.runtime.profile)),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        if (onLoadMore != null && movements.length < totalCount) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(tr.text('load_more')),
            ),
          ),
        ],
      ],
    );
  }
}

class _WasteLossReport extends StatelessWidget {
  const _WasteLossReport({
    required this.store,
    required this.canManageWaste,
  });
  final ApplicationSession store;
  final bool canManageWaste;
  static final RevisionKeyCache<List<StockMovement>> _rowsCache =
      RevisionKeyCache<List<StockMovement>>();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!store.security.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
    })) {
      return _InventorySectionDenied(
        title: tr.text('waste_loss_report'),
        message: tr.text('waste_loss_reporting_no_access'),
      );
    }
    final lossMovements = _rowsCache.getOrCompute(
      store.inventory.revision,
      store.runtime.identity.storeId,
      () => store.inventory.stockMovements
          .where((item) =>
              item.type == 'inventory_loss' ||
              (item.type == 'inventory_adjustment' && item.quantity < 0))
          .toList(growable: false),
    );
    return _WasteLossReportView(
      store: store,
      movements: lossMovements,
      totalCount: lossMovements.length,
      canManageWaste: canManageWaste,
      onDelete: (movement) => store.inventory.deleteWasteLoss(movement.id),
    );
  }
}

class _InventoryAccessDenied extends StatelessWidget {
  const _InventoryAccessDenied({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
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

class _InventorySectionDenied extends StatelessWidget {
  const _InventorySectionDenied({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        _InventoryAccessDenied(title: title, message: message),
      ],
    );
  }
}

class _WasteTotal {
  double quantity = 0;
  double value = 0;
  int count = 0;
}

String _adjustmentCategoryLabel(AppLocalizations tr, String key) {
  switch (key) {
    case 'damage':
      return tr.text('adjustment_damage');
    case 'expired':
      return tr.text('adjustment_expired');
    case 'free_sample':
      return tr.text('adjustment_free_sample');
    case 'internal_consumption':
      return tr.text('adjustment_internal_consumption');
    case 'stock_count_shortage':
      return tr.text('adjustment_stock_count_shortage');
    case 'stock_count_overage':
      return tr.text('adjustment_stock_count_overage');
    default:
      return tr.text('adjustment_other');
  }
}
