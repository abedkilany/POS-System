part of 'inventory_page.dart';

class _MovementsListState extends State<_MovementsList> {
  static final RevisionKeyCache<List<StockMovement>> _movementsCache =
      RevisionKeyCache<List<StockMovement>>();
  Future<_StockMovementsQueryResult?>? _movementsFuture;
  String _movementsFutureKey = '';
  int _visibleMovementCount = 100;
  String _movementQuery = '';
  String _movementType = 'all';
  String _movementWarehouseId = '';
  final TextEditingController _movementSearchController =
      TextEditingController();

  static const List<String> _commonMovementTypes = <String>[
    'purchase_receive',
    'purchase_return',
    'purchase_cancel',
    'sale',
    'sale_return',
    'sale_restore',
    'sale_cancel',
    'transfer_in',
    'transfer_out',
    'count_adjustment',
    'inventory_loss',
    'inventory_adjustment',
    'manufacturing_consume',
    'manufacturing_produce',
    'auto_correction',
  ];

  List<String> _movementTypeOptions() {
    final types = <String>{..._commonMovementTypes};
    types.addAll(
        widget.store.inventory.stockMovements.map((movement) => movement.type));
    return <String>['all', ...types.where((type) => type.trim().isNotEmpty)];
  }

  List<Warehouse> _warehouseOptions() => widget.store.inventory.warehouses
      .where((warehouse) => !warehouse.isDeleted)
      .toList(growable: false);

  void _resetMovementFilters() {
    setState(() {
      _movementQuery = '';
      _movementType = 'all';
      _movementWarehouseId = '';
      _movementSearchController.clear();
      _visibleMovementCount = 100;
      _movementsFuture = null;
      _movementsFutureKey = '';
    });
  }

  @override
  void didUpdateWidget(covariant _MovementsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _movementsFuture = null;
      _movementsFutureKey = '';
      _visibleMovementCount = 100;
    }
  }

  @override
  void dispose() {
    _movementSearchController.dispose();
    super.dispose();
  }

  Future<_StockMovementsQueryResult?> _queryMovementsFromSqlite() {
    final limit = _visibleMovementCount.clamp(1, 500).toInt();
    final query = _movementQuery.trim();
    final key =
        '${widget.store.inventory.revision}|$query|$_movementType|$_movementWarehouseId|$limit';
    if (_movementsFuture == null || _movementsFutureKey != key) {
      _movementsFutureKey = key;
      _movementsFuture = () async {
        final page = await LocalDatabaseService.queryStockMovementsFromSqlite(
          query: query,
          type: _movementType,
          warehouseId: _movementWarehouseId,
          limit: limit,
          sortMode: 'newest',
        );
        if (page == null) return null;
        return _StockMovementsQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _movementsFuture!;
  }

  void _loadMoreMovements(int totalCount) {
    setState(() {
      _visibleMovementCount = math.min(totalCount, _visibleMovementCount + 100);
      _movementsFuture = null;
    });
  }

  bool _isActiveManualAdjustment(StockMovement movement) {
    if (movement.movementGroupId.trim().isEmpty ||
        movement.reversalOfMovementId.isNotEmpty ||
        (movement.type != 'inventory_loss' &&
            movement.type != 'inventory_adjustment')) {
      return false;
    }
    return !widget.store.inventory.stockMovements.any(
      (candidate) => candidate.reversalOfMovementId == movement.id,
    );
  }

  Future<void> _editManualAdjustment(StockMovement movement) async {
    final tr = AppLocalizations.of(context);
    final operationId = movement.movementGroupId.trim();
    if (operationId.isEmpty) return;
    final all = widget.store.inventory.stockMovements;
    final reversedIds = <String>{
      for (final candidate in all)
        if (candidate.reversalOfMovementId.trim().isNotEmpty)
          candidate.reversalOfMovementId.trim(),
    };
    final active = all
        .where(
          (candidate) =>
              candidate.movementGroupId == operationId &&
              candidate.reversalOfMovementId.isEmpty &&
              !reversedIds.contains(candidate.id) &&
              (candidate.type == 'inventory_loss' ||
                  candidate.type == 'inventory_adjustment'),
        )
        .toList(growable: false);
    if (active.isEmpty) return;
    final first = active.first;
    final delta = active.fold<double>(
      0,
      (sum, candidate) => sum + candidate.quantity,
    );
    final product = widget.store.catalog.stockTrackedProducts
        .where((item) => item.id == first.productId)
        .firstOrNull;
    if (product == null) return;
    final expectedVersion =
        await widget.store.inventory.manualStockAdjustmentVersion(operationId);
    if (!mounted || expectedVersion <= 0) return;

    final quantityController = TextEditingController(text: delta.toString());
    final notesController = TextEditingController(text: first.notes);
    final evidenceController = TextEditingController(text: first.evidenceRef);
    var category = first.adjustmentCategory.trim().isEmpty
        ? 'other'
        : first.adjustmentCategory.trim();
    final categories = <String, String>{
      'damage': tr.text('adjustment_damage'),
      'expired': tr.text('adjustment_expired'),
      'free_sample': tr.text('adjustment_free_sample'),
      'internal_consumption': tr.text('adjustment_internal_consumption'),
      'stock_count_shortage': tr.text('adjustment_stock_count_shortage'),
      'stock_count_overage': tr.text('adjustment_stock_count_overage'),
      'other': tr.text('adjustment_other'),
    };
    if (!categories.containsKey(category)) category = 'other';

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text('${tr.text('edit')} • ${product.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tr.text('warehouse')}: ${first.warehouseName}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(
                      labelText: tr.text('adjustment_reason_type'),
                    ),
                    items: categories.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => category = value ?? category,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr.text('quantity_delta'),
                      helperText: tr.text('quantity_delta_help'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration:
                        InputDecoration(labelText: tr.text('notes_optional')),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: evidenceController,
                    decoration: InputDecoration(
                      labelText: tr.text('evidence_optional'),
                    ),
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
                  final nextDelta =
                      double.tryParse(quantityController.text.trim()) ?? 0;
                  if (nextDelta.abs() <= 0.000001) return;
                  List<BatchAllocation> allocations = const <BatchAllocation>[];
                  if (product.expiryTrackingEnabled && nextDelta > 0) {
                    final selected = await showBatchAllocationDialog(
                      dialogContext,
                      product: product,
                      expectedQuantity: nextDelta,
                      sourceId: '$operationId-edit-v${expectedVersion + 1}',
                    );
                    if (selected == null) return;
                    allocations = selected;
                  }
                  await widget.store.inventory.editStockAdjustment(
                    operationReferenceId: operationId,
                    expectedVersion: expectedVersion,
                    quantityDelta: nextDelta,
                    reason: categories[category] ?? category,
                    adjustmentCategory: category,
                    notes: notesController.text,
                    evidenceRef: evidenceController.text,
                    batchAllocations: allocations,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(tr.text('save')),
              ),
            ],
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _movementsFuture = null;
          _movementsFutureKey = '';
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizedErrorText(tr, error))),
        );
      }
    } finally {
      quantityController.dispose();
      notesController.dispose();
      evidenceController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
    })) {
      return _InventorySectionDenied(
        title: tr.text('stock_movements'),
        message: tr.text('stock_movement_history_no_access'),
      );
    }
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_StockMovementsQueryResult?>(
        future: _queryMovementsFromSqlite(),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildMovementsView(
              context,
              tr,
              result.items,
              totalCount: result.totalCount,
              loading: snapshot.connectionState == ConnectionState.waiting &&
                  result.items.isEmpty,
              onLoadMore: result.hasMore
                  ? () => _loadMoreMovements(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildMovementsView(
              context,
              tr,
              const <StockMovement>[],
              totalCount: 0,
              loading: true,
            );
          }
          return _buildMovementsFromMemory(context, tr);
        },
      );
    }
    return _buildMovementsFromMemory(context, tr);
  }

  Widget _buildMovementsFromMemory(BuildContext context, AppLocalizations tr) {
    final movements = _movementsCache.getOrCompute(
      widget.store.inventory.revision,
      widget.store.runtime.identity.storeId,
      () => widget.store.inventory.stockMovements.toList(growable: false),
    );
    final filtered =
        movements.where(_matchesMovementFilters).toList(growable: false);
    final visible =
        filtered.take(_visibleMovementCount).toList(growable: false);
    return _buildMovementsView(
      context,
      tr,
      visible,
      totalCount: filtered.length,
      onLoadMore: visible.length < filtered.length
          ? () => _loadMoreMovements(filtered.length)
          : null,
    );
  }

  bool _matchesMovementFilters(StockMovement movement) {
    if (_movementType != 'all' && movement.type != _movementType) {
      return false;
    }
    if (_movementWarehouseId.isNotEmpty &&
        movement.warehouseId != _movementWarehouseId) {
      return false;
    }
    final query = _movementQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final searchable = [
      movement.productName,
      movement.warehouseName,
      movement.referenceNo,
      movement.referenceId,
      movement.reason,
      movement.notes,
      movement.type,
      _movementTypeLabel(AppLocalizations.of(context), movement.type),
    ].join(' ').toLowerCase();
    return searchable.contains(query);
  }

  Widget _buildMovementFilters(BuildContext context, AppLocalizations tr) {
    final warehouses = _warehouseOptions();
    final movementTypes = _movementTypeOptions();
    final selectedWarehouseId = warehouses.any(
      (warehouse) => warehouse.id == _movementWarehouseId,
    )
        ? _movementWarehouseId
        : 'all';
    final filterWidth =
        math.min(420.0, math.max(220.0, MediaQuery.sizeOf(context).width - 40));
    final hasFilters = _movementQuery.trim().isNotEmpty ||
        _movementType != 'all' ||
        _movementWarehouseId.isNotEmpty;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: filterWidth,
          child: TextField(
            controller: _movementSearchController,
            decoration: InputDecoration(
              labelText: tr.text('search_stock_movements'),
              hintText: tr.text('search_stock_movements_hint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _movementQuery.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr.text('clear_filters'),
                      onPressed: () {
                        _movementSearchController.clear();
                        setState(() {
                          _movementQuery = '';
                          _visibleMovementCount = 100;
                          _movementsFuture = null;
                        });
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() {
              _movementQuery = value;
              _visibleMovementCount = 100;
              _movementsFuture = null;
            }),
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<String>(
            initialValue:
                movementTypes.contains(_movementType) ? _movementType : 'all',
            decoration: InputDecoration(
              labelText: tr.text('movement_type_filter'),
              prefixIcon: const Icon(Icons.swap_vert),
            ),
            items: movementTypes
                .map((type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type == 'all'
                          ? tr.text('all_movement_types')
                          : _movementTypeLabel(tr, type)),
                    ))
                .toList(growable: false),
            onChanged: (value) => setState(() {
              _movementType = value ?? 'all';
              _visibleMovementCount = 100;
              _movementsFuture = null;
            }),
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<String>(
            initialValue: selectedWarehouseId,
            decoration: InputDecoration(
              labelText: tr.text('warehouse_filter'),
              prefixIcon: const Icon(Icons.warehouse_outlined),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'all',
                child: Text(tr.text('all_warehouses')),
              ),
              ...warehouses.map((warehouse) => DropdownMenuItem<String>(
                    value: warehouse.id,
                    child: Text(warehouse.name),
                  )),
            ],
            onChanged: (value) => setState(() {
              _movementWarehouseId =
                  value == null || value == 'all' ? '' : value;
              _visibleMovementCount = 100;
              _movementsFuture = null;
            }),
          ),
        ),
        if (hasFilters)
          OutlinedButton.icon(
            onPressed: _resetMovementFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(tr.text('clear_filters')),
          ),
      ],
    );
  }

  Widget _buildMovementsView(
    BuildContext context,
    AppLocalizations tr,
    List<StockMovement> movements, {
    required int totalCount,
    bool loading = false,
    VoidCallback? onLoadMore,
  }) {
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        PageDataLoadIndicator(
          loadedCount: movements.length,
          totalCount: totalCount,
        ),
        const SizedBox(height: 12),
        _buildMovementFilters(context, tr),
        const SizedBox(height: 12),
        Card(
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              : movements.isEmpty
                  ? Padding(
                      padding: VentioResponsive.pageInsets(context),
                      child: Text(tr.text('no_stock_movements')))
                  : Column(
                      children: [
                        for (final movement in movements) ...[
                          ListTile(
                            leading: CircleAvatar(
                                child: Icon(movement.quantity >= 0
                                    ? Icons.add
                                    : Icons.remove)),
                            title: Text(movement.productName),
                            subtitle: Text(
                                "${_movementTypeLabel(tr, movement.type)} • ${movement.warehouseName} • ${movement.referenceNo} • ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}${movement.notes.isNotEmpty ? ' • ${movement.notes}' : ''}${movement.evidenceRef.isNotEmpty ? ' • ${tr.text('evidence')}: ${movement.evidenceRef}' : ''}"),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      movement.quantity > 0
                                          ? '+${movement.quantity}'
                                          : '${movement.quantity}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (movement.unitCost > 0)
                                      Text(formatUsdReferenceAmount(
                                        movement.value,
                                        widget.store.runtime.profile,
                                      )),
                                  ],
                                ),
                                if (widget.store.security.hasPermission(
                                      AppPermission.inventoryCorrectionsManage,
                                    ) &&
                                    _isActiveManualAdjustment(movement))
                                  IconButton(
                                    tooltip: tr.text('edit'),
                                    onPressed: () =>
                                        _editManualAdjustment(movement),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                              ],
                            ),
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

class _AutoCorrectionsTab extends StatefulWidget {
  const _AutoCorrectionsTab({required this.store});

  final AppStore store;

  @override
  State<_AutoCorrectionsTab> createState() => _AutoCorrectionsTabState();
}
