part of 'inventory_page.dart';

class _AutoCorrectionsTabState extends State<_AutoCorrectionsTab> {
  bool showReviewed = false;
  final RevisionKeyCache<List<StockMovement>> _allCache =
      RevisionKeyCache<List<StockMovement>>();
  final RevisionKeyCache<List<StockMovement>> _pendingCache =
      RevisionKeyCache<List<StockMovement>>();
  Future<_StockMovementsQueryResult?>? _correctionsFuture;
  Future<_StockMovementsQueryResult?>? _pendingCountFuture;
  Future<_StockMovementsQueryResult?>? _allCountFuture;
  String _correctionsFutureKey = '';
  String _pendingCountFutureKey = '';
  String _allCountFutureKey = '';
  int _visibleCorrectionCount = 100;

  @override
  void didUpdateWidget(covariant _AutoCorrectionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _allCache.invalidate();
      _pendingCache.invalidate();
      _correctionsFuture = null;
      _pendingCountFuture = null;
      _allCountFuture = null;
      _correctionsFutureKey = '';
      _pendingCountFutureKey = '';
      _allCountFutureKey = '';
      _visibleCorrectionCount = 100;
    }
  }

  Future<_StockMovementsQueryResult?> _queryCorrectionsFromSqlite({
    required bool reviewed,
    required int limit,
  }) {
    final key = '${widget.store.inventory.revision}|$reviewed|$limit';
    if (_correctionsFuture == null || _correctionsFutureKey != key) {
      _correctionsFutureKey = key;
      _correctionsFuture = () async {
        final page = await LocalDatabaseService.queryStockMovementsFromSqlite(
          type: 'auto_correction',
          reviewed: reviewed,
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
    return _correctionsFuture!;
  }

  Future<_StockMovementsQueryResult?> _queryPendingCorrectionsCount() {
    final key = '${widget.store.inventory.revision}|pending_count';
    if (_pendingCountFuture == null || _pendingCountFutureKey != key) {
      _pendingCountFutureKey = key;
      _pendingCountFuture = () async {
        final page = await LocalDatabaseService.queryStockMovementsFromSqlite(
          type: 'auto_correction',
          reviewed: false,
          limit: 1,
          sortMode: 'newest',
        );
        if (page == null) return null;
        return _StockMovementsQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _pendingCountFuture!;
  }

  Future<_StockMovementsQueryResult?> _queryAllCorrectionsCount() {
    final key = '${widget.store.inventory.revision}|all_count';
    if (_allCountFuture == null || _allCountFutureKey != key) {
      _allCountFutureKey = key;
      _allCountFuture = () async {
        final page = await LocalDatabaseService.queryStockMovementsFromSqlite(
          type: 'auto_correction',
          limit: 1,
          sortMode: 'newest',
        );
        if (page == null) return null;
        return _StockMovementsQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _allCountFuture!;
  }

  void _loadMoreCorrections(int totalCount) {
    setState(() {
      _visibleCorrectionCount =
          math.min(totalCount, _visibleCorrectionCount + 100);
      _correctionsFuture = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canReview = widget.store.security.hasPermission(
      AppPermission.inventoryCorrectionsManage,
    );
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
    })) {
      return _InventorySectionDenied(
        title: tr.text('auto_corrections'),
        message: tr.text('auto_correction_review_no_access'),
      );
    }
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      final reviewed = showReviewed;
      final limit = _visibleCorrectionCount.clamp(1, 500).toInt();
      return FutureBuilder<_StockMovementsQueryResult?>(
        future: _queryCorrectionsFromSqlite(
          reviewed: reviewed,
          limit: limit,
        ),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (result == null || snapshot.hasError) {
            return _buildCorrectionsFromMemory(context, tr, canReview);
          }
          return FutureBuilder<List<_StockMovementsQueryResult?>>(
            future: Future.wait(<Future<_StockMovementsQueryResult?>>[
              _queryPendingCorrectionsCount(),
              _queryAllCorrectionsCount(),
            ]),
            builder: (context, countSnapshot) {
              final counts = countSnapshot.data;
              final pendingCount = counts?[0]?.totalCount ?? result.totalCount;
              final allCount = counts?[1]?.totalCount ?? result.totalCount;
              return _buildCorrectionsView(context, tr,
                  canReview: canReview,
                  corrections: result.items,
                  totalCount: result.totalCount,
                  pendingCount: pendingCount,
                  allCount: allCount,
                  onLoadMore: result.hasMore
                      ? () => _loadMoreCorrections(result.totalCount)
                      : null);
            },
          );
        },
      );
    }
    return _buildCorrectionsFromMemory(context, tr, canReview);
  }

  Widget _buildCorrectionsFromMemory(
    BuildContext context,
    AppLocalizations tr,
    bool canReview,
  ) {
    final allCorrections = _allCache.getOrCompute(
      widget.store.inventory.revision,
      widget.store.runtime.identity.storeId,
      () => widget.store.inventory.autoCorrectionMovements
          .toList(growable: false),
    );
    final pending = _pendingCache.getOrCompute(
      widget.store.inventory.revision,
      '${widget.store.runtime.identity.storeId}|pending',
      () => widget.store.inventory.pendingAutoCorrectionMovements
          .toList(growable: false),
    );
    final corrections = showReviewed ? allCorrections : pending;
    return _buildCorrectionsView(
      context,
      tr,
      canReview: canReview,
      corrections: corrections,
      totalCount: corrections.length,
      pendingCount: pending.length,
      allCount: allCorrections.length,
    );
  }

  Widget _buildCorrectionsView(
    BuildContext context,
    AppLocalizations tr, {
    required bool canReview,
    required List<StockMovement> corrections,
    required int totalCount,
    required int pendingCount,
    required int allCount,
    VoidCallback? onLoadMore,
  }) {
    double totalQty = 0;
    double totalValue = 0;
    for (final item in corrections) {
      totalQty += item.quantity.abs();
      totalValue += item.value;
    }

    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('pending_auto_corrections'),
                value: '$pendingCount',
                icon: Icons.notifications_active_outlined),
            SummaryCard(
                title: tr.text('auto_corrections'),
                value: '$allCount',
                icon: Icons.inventory_outlined),
            SummaryCard(
                title: tr.text('quantity'),
                value: totalQty.toStringAsFixed(
                    totalQty.truncateToDouble() == totalQty ? 0 : 2),
                icon: Icons.add_box_outlined),
            SummaryCard(
                title: tr.text('estimated_value'),
                value: formatUsdReferenceAmount(
                    totalValue, widget.store.runtime.profile),
                icon: Icons.payments_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            value: showReviewed,
            onChanged: (value) => setState(() => showReviewed = value),
            title: Text(tr.text('show_reviewed_corrections')),
            subtitle: Text(tr.text('show_reviewed_corrections_desc')),
            secondary: const Icon(Icons.history_outlined),
          ),
        ),
        const SizedBox(height: 12),
        PageDataLoadIndicator(
          loadedCount: corrections.length,
          totalCount: totalCount,
        ),
        const SizedBox(height: 12),
        Card(
          child: corrections.isEmpty
              ? Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Text(showReviewed
                      ? tr.text('no_auto_corrections')
                      : tr.text('no_pending_auto_corrections')),
                )
              : Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.fact_check_outlined)),
                      title: Text(tr.text('auto_corrections_need_review'),
                          style: Theme.of(context).textTheme.titleMedium),
                      subtitle:
                          Text(tr.text('auto_corrections_need_review_desc')),
                    ),
                    const Divider(height: 1),
                    for (final movement in corrections) ...[
                      ListTile(
                        leading: CircleAvatar(
                          child: Icon(movement.isReviewed
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded),
                        ),
                        title: Text(movement.productName),
                        subtitle: Text([
                          '${tr.text('quantity')}: +${movement.quantity}',
                          if (movement.referenceNo.isNotEmpty)
                            '${tr.text('invoice')}: ${movement.referenceNo}',
                          movement.date.toLocal().toString().split('.').first,
                          if (movement.deviceId.isNotEmpty)
                            '${tr.text('device')}: ${movement.deviceId}',
                          if (movement.reviewedBy.isNotEmpty)
                            '${tr.text('reviewed_by')}: ${movement.reviewedBy}',
                        ].join(' • ')),
                        isThreeLine: true,
                        trailing: movement.isReviewed
                            ? const Icon(Icons.done_all_outlined)
                            : canReview
                                ? FilledButton.icon(
                                    onPressed: () =>
                                        _reviewMovement(movement.id),
                                    icon: const Icon(Icons.check),
                                    label: Text(tr.text('mark_reviewed')),
                                  )
                                : const Icon(Icons.lock_outline),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        if (onLoadMore != null && corrections.length < totalCount) ...[
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

  Future<void> _reviewMovement(String id) async {
    final tr = AppLocalizations.of(context);
    try {
      await widget.store.inventory.reviewAutoCorrection(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr.text('auto_correction_marked_reviewed'))));
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }
}

class _StockCountTab extends StatefulWidget {
  const _StockCountTab({required this.store});

  final ApplicationSession store;

  @override
  State<_StockCountTab> createState() => _StockCountTabState();
}

class _StockCountTabState extends State<_StockCountTab> {
  String query = '';
  final RevisionKeyCache<List<Product>> _productsCache =
      RevisionKeyCache<List<Product>>();
  final RevisionKeyCache<Map<String, InventoryCountLine>> _lineLookupCache =
      RevisionKeyCache<Map<String, InventoryCountLine>>();
  final RevisionKeyCache<Map<String, int>> _movementCountCache =
      RevisionKeyCache<Map<String, int>>();
  Future<Map<String, int>?>? _movementCountsFuture;
  String _movementCountsFutureKey = '';

  @override
  void didUpdateWidget(covariant _StockCountTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _productsCache.invalidate();
      _lineLookupCache.invalidate();
      _movementCountCache.invalidate();
      _movementCountsFuture = null;
      _movementCountsFutureKey = '';
    }
  }

  Map<String, DateTime> _countedAtByProduct(InventoryCountSession? active) {
    final result = <String, DateTime>{};
    if (active == null) return result;
    for (final line in active.lines) {
      final countedAt = line.countedAt;
      if (countedAt == null) continue;
      result[line.productId] = countedAt;
    }
    return result;
  }

  Map<String, int> _movementCountsFromMemory(
    InventoryCountSession? active,
    Map<String, DateTime> countedAtByProduct,
  ) {
    return _movementCountCache.getOrCompute(
      widget.store.inventory.revision,
      active?.id ?? 'no_active',
      () {
        final counts = <String, int>{
          for (final productId in countedAtByProduct.keys) productId: 0,
        };
        for (final movement in widget.store.inventory.stockMovements) {
          final countedAt = countedAtByProduct[movement.productId];
          if (countedAt == null) continue;
          if (movement.type == 'count_adjustment' ||
              !movement.date.isAfter(countedAt)) {
            continue;
          }
          counts[movement.productId] = (counts[movement.productId] ?? 0) + 1;
        }
        return counts;
      },
    );
  }

  Future<Map<String, int>?> _movementCountsFromSqlite(
    InventoryCountSession? active,
    Map<String, DateTime> countedAtByProduct,
  ) {
    if (countedAtByProduct.isEmpty ||
        !LocalDatabaseService.canQueryBusinessSqlite) {
      return Future<Map<String, int>?>.value(null);
    }
    final key =
        '${widget.store.inventory.revision}|${active?.id ?? 'no_active'}|${countedAtByProduct.length}';
    if (_movementCountsFuture == null || _movementCountsFutureKey != key) {
      _movementCountsFutureKey = key;
      _movementCountsFuture =
          LocalDatabaseService.countStockMovementsAfterByProductFromSqlite(
              countedAtByProduct);
    }
    return _movementCountsFuture!;
  }

  Widget _buildActiveStockCountCard(
    AppLocalizations tr,
    InventoryCountSession active,
    List<Product> products,
    Map<String, InventoryCountLine> lineLookup,
    Map<String, int> movementCounts,
  ) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
            title: Text('${tr.text('active_stock_count')} • ${active.countNo}'),
            subtitle: Text(
                '${tr.text('warehouse')}: ${active.warehouseName} • ${tr.text('started_at')}: ${active.createdAt.toLocal().toString().split('.').first}'),
          ),
          const Divider(height: 1),
          for (final product in products.take(200))
            _StockCountProductTile(
                store: widget.store,
                product: product,
                line: lineLookup[product.id],
                movementsAfter: movementCounts[product.id] ?? 0),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryCountsManage,
    )) {
      return _InventorySectionDenied(
        title: tr.text('stock_count'),
        message: tr.text('stock_count_actions_no_access'),
      );
    }
    final sessions = widget.store.inventory.inventoryCountSessions;
    final active = widget.store.inventory.activeInventoryCountSession;
    final lineLookup = _lineLookupCache.getOrCompute(
      widget.store.inventory.revision,
      active?.id ?? 'no_active',
      () {
        final map = <String, InventoryCountLine>{};
        if (active != null) {
          for (final line in active.lines) {
            map[line.productId] = line;
          }
        }
        return map;
      },
    );
    final countedAtByProduct = _countedAtByProduct(active);
    final fallbackMovementCounts =
        _movementCountsFromMemory(active, countedAtByProduct);
    final needle = query.trim().toLowerCase();
    final products = _productsCache.getOrCompute(
      widget.store.inventory.revision,
      '${active?.id ?? 'no_active'}|$needle',
      () => widget.store.catalog.stockTrackedProducts.where((product) {
        if (active == null || needle.isEmpty) return true;
        return product.name.toLowerCase().contains(needle) ||
            product.code.toLowerCase().contains(needle);
      }).toList(growable: false),
    );

    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('stock_count_sessions'),
                value: '${sessions.length}',
                icon: Icons.assignment_outlined),
            SummaryCard(
                title: tr.text('open_stock_count'),
                value: active == null ? '0' : '1',
                icon: Icons.pending_actions_outlined),
            if (active != null)
              SummaryCard(
                  title: tr.text('counted_products'),
                  value: '${active.countedLines}/${active.totalLines}',
                  icon: Icons.fact_check_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('stock_count'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(tr.text('stock_count_desc')),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: active == null ? _startCount : null,
                      icon: const Icon(Icons.add_task_outlined),
                      label: Text(tr.text('start_stock_count')),
                    ),
                    if (active != null) ...[
                      FilledButton.icon(
                        onPressed: active.countedLines == 0
                            ? null
                            : () => _approveCount(active.id),
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(tr.text('approve_stock_count')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _cancelCount(active.id),
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(tr.text('cancel')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (active != null) ...[
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: tr.text('search_products')),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, int>?>(
            future: _movementCountsFromSqlite(active, countedAtByProduct),
            builder: (context, snapshot) {
              return _buildActiveStockCountCard(
                tr,
                active,
                products,
                lineLookup,
                snapshot.data ?? fallbackMovementCounts,
              );
            },
          ),
          /*
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_outlined)),
                  title: Text(
                      '${tr.text('active_stock_count')} • ${active.countNo}'),
                  subtitle: Text(
                      '${tr.text('warehouse')}: ${active.warehouseName} • ${tr.text('started_at')}: ${active.createdAt.toLocal().toString().split('.').first}'),
                ),
                const Divider(height: 1),
                for (final product in products.take(200))
                  _StockCountProductTile(
                      store: widget.store,
                      product: product,
                      line: lineLookup[product.id],
                      movementsAfter: movementCounts[product.id] ?? 0),
              ],
            ),
          ),
          */
        ],
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(tr.text('previous_stock_counts')),
              ),
              const Divider(height: 1),
              if (sessions.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr.text('no_stock_counts')))
              else
                for (final session in sessions.take(20))
                  ListTile(
                    leading: Icon(session.isApproved
                        ? Icons.verified_outlined
                        : session.isReversed
                            ? Icons.undo_outlined
                            : session.isOpen
                                ? Icons.pending_actions_outlined
                                : Icons.cancel_outlined),
                    title: Text(session.countNo),
                    subtitle: Text(
                        '${tr.text('status')}: ${session.status} • ${tr.text('warehouse')}: ${session.warehouseName} • ${tr.text('counted_products')}: ${session.countedLines}/${session.totalLines}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(session.createdAt
                            .toLocal()
                            .toString()
                            .split(' ')
                            .first),
                        if (session.isApproved) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: tr.text('reverse_approved_count'),
                            onPressed: () => _reverseCount(session),
                            icon: const Icon(Icons.undo_outlined),
                          ),
                        ],
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startCount() async {
    try {
      final tr = AppLocalizations.of(context);
      final selected = await showDialog<Warehouse>(
        context: context,
        builder: (dialogContext) {
          final initial = widget.store.inventory.resolveWarehouseForPurchase();
          var selectedWarehouse = initial;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(tr.text('start_stock_count')),
              content: DropdownButtonFormField<String>(
                initialValue: selectedWarehouse.id,
                decoration: InputDecoration(labelText: tr.text('warehouse')),
                items: widget.store.inventory.warehouses
                    .map(
                      (warehouse) => DropdownMenuItem<String>(
                        value: warehouse.id,
                        child: Text(warehouse.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedWarehouse = widget.store.inventory
                        .resolveWarehouseForPurchase(warehouseId: value ?? '');
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel')),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selectedWarehouse),
                  child: Text(tr.text('start')),
                ),
              ],
            ),
          );
        },
      );
      if (selected == null) return;
      await widget.store.inventory.createInventoryCountSession(
        warehouseId: selected.id,
        warehouseName: selected.name,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }

  Future<void> _approveCount(String id) async {
    try {
      await widget.store.inventory.approveInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }

  Future<void> _reverseCount(InventoryCountSession session) async {
    final reasonController = TextEditingController();
    try {
      final tr = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr.text('reverse_approved_count')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr
                  .format('reverse_count_message', {'count': session.countNo})),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: tr.text('reversal_reason'),
                  hintText: tr.text('reversal_reason_hint'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('reverse_count')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.store.inventory.reverseInventoryCount(
        session.id,
        reason: reasonController.text.trim(),
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _cancelCount(String id) async {
    try {
      await widget.store.inventory.cancelInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(localizedErrorText(AppLocalizations.of(context), error))));
      }
    }
  }
}
