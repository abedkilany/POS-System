part of 'inventory_page.dart';

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  String query = '';
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController =
      TabController(length: 7, vsync: this);
  Future<_InventoryProductsResult?>? _inventoryProductsFuture;
  String _inventoryProductsFutureKey = '';
  int _visibleInventoryProductCount = 100;
  final RevisionKeyCache<List<Product>> _filteredProductsCache =
      RevisionKeyCache<List<Product>>();
  final RevisionValueCache<_InventoryOverviewMetrics> _overviewCache =
      RevisionValueCache<_InventoryOverviewMetrics>();

  Future<double> _warehouseStock(
    String productId,
    String warehouseId,
  ) async {
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return widget.store.warehouseStockFromSqlite(
        productId,
        warehouseId: warehouseId,
      );
    }
    return widget.store.stockForWarehouse(productId, warehouseId);
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _inventoryProductsFuture = null;
      _inventoryProductsFutureKey = '';
      _visibleInventoryProductCount = 100;
      _filteredProductsCache.invalidate();
      _overviewCache.invalidate();
    }
  }

  Future<void> _scanInventorySearchBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PageTimingScope(
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(),
        ),
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() {
      query = code.trim();
      _searchController.text = query;
      _visibleInventoryProductCount = 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewInventory) {
      return _InventoryAccessDenied(
        title: tr.text('inventory'),
        message: tr.text('no_access_current_role'),
      );
    }
    if (!widget.store.isCoreDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final normalizedQuery = query.trim().toLowerCase();
    final overview = _overviewCache.getOrCompute(
      widget.store.inventoryRevision,
      () => _InventoryOverviewMetrics.fromStore(widget.store),
    );
    final canViewOverview =
        widget.store.hasPermission(AppPermission.inventoryView) ||
            widget.store.hasPermission(AppPermission.reportsView) ||
            widget.store.hasPermission(AppPermission.productsCreate) ||
            widget.store.hasPermission(AppPermission.productsEdit) ||
            widget.store.hasPermission(AppPermission.productsDelete);
    final canManageWarehouses =
        widget.store.hasPermission(AppPermission.inventoryWarehousesManage);
    final canViewMovements = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
    });
    final canViewCorrections = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
    });
    final canManageCounts =
        widget.store.hasPermission(AppPermission.inventoryCountsManage);
    final canViewWasteLoss = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
    });
    final canManageWaste = widget.store.hasPermission(
      AppPermission.inventoryWasteManage,
    );

    if (!canViewOverview &&
        !canManageWarehouses &&
        !canViewMovements &&
        !canViewCorrections &&
        !canManageCounts &&
        !canViewWasteLoss) {
      return _InventoryAccessDenied(
        title: tr.text('inventory'),
        message: tr.text('no_access_current_role'),
      );
    }

    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_InventoryProductsResult?>(
        future: _queryInventoryProductsFromSqlite(normalizedQuery),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildInventoryShell(
              tr,
              products: result.items,
              productsTotalCount: result.totalCount,
              overview: overview,
              canManageWarehouses: canManageWarehouses,
              canViewMovements: canViewMovements,
              canViewCorrections: canViewCorrections,
              canManageCounts: canManageCounts,
              canViewWasteLoss: canViewWasteLoss,
              canManageWaste: canManageWaste,
              loadingProducts:
                  snapshot.connectionState == ConnectionState.waiting &&
                      result.items.isEmpty,
              onLoadMoreProducts: result.hasMore
                  ? () => _loadMoreInventoryProducts(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildInventoryShell(
              tr,
              products: const <Product>[],
              productsTotalCount: 0,
              overview: overview,
              canManageWarehouses: canManageWarehouses,
              canViewMovements: canViewMovements,
              canViewCorrections: canViewCorrections,
              canManageCounts: canManageCounts,
              canViewWasteLoss: canViewWasteLoss,
              canManageWaste: canManageWaste,
              loadingProducts: true,
            );
          }
          final fallbackProducts = _productsFromMemory(normalizedQuery);
          return _buildInventoryShell(
            tr,
            products: fallbackProducts,
            productsTotalCount: fallbackProducts.length,
            overview: overview,
            canManageWarehouses: canManageWarehouses,
            canViewMovements: canViewMovements,
            canViewCorrections: canViewCorrections,
            canManageCounts: canManageCounts,
            canViewWasteLoss: canViewWasteLoss,
            canManageWaste: canManageWaste,
          );
        },
      );
    }

    final products = _productsFromMemory(normalizedQuery);
    return _buildInventoryShell(
      tr,
      products: products,
      productsTotalCount: products.length,
      overview: overview,
      canManageWarehouses: canManageWarehouses,
      canViewMovements: canViewMovements,
      canViewCorrections: canViewCorrections,
      canManageCounts: canManageCounts,
      canViewWasteLoss: canViewWasteLoss,
      canManageWaste: canManageWaste,
    );
  }

  List<Product> _productsFromMemory(String normalizedQuery) {
    return _filteredProductsCache.getOrCompute(
      widget.store.inventoryRevision,
      normalizedQuery,
      () => _filterProducts(widget.store.stockTrackedProducts, normalizedQuery),
    );
  }

  Future<_InventoryProductsResult?> _queryInventoryProductsFromSqlite(
    String normalizedQuery,
  ) {
    final limit = _visibleInventoryProductCount.clamp(1, 500).toInt();
    final key = '${widget.store.inventoryRevision}|$normalizedQuery|$limit';
    if (_inventoryProductsFuture == null ||
        _inventoryProductsFutureKey != key) {
      _inventoryProductsFutureKey = key;
      _inventoryProductsFuture = () async {
        final page = await LocalDatabaseService.queryProductsFromSqlite(
          query: normalizedQuery,
          limit: limit,
          stockTrackedOnly: true,
        );
        if (page == null) return null;
        return _InventoryProductsResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _inventoryProductsFuture!;
  }

  void _loadMoreInventoryProducts(int totalCount) {
    setState(() {
      _visibleInventoryProductCount =
          math.min(totalCount, _visibleInventoryProductCount + 100);
    });
  }

  Widget _buildInventoryShell(
    AppLocalizations tr, {
    required List<Product> products,
    required int productsTotalCount,
    required _InventoryOverviewMetrics overview,
    required bool canManageWarehouses,
    required bool canViewMovements,
    required bool canViewCorrections,
    required bool canManageCounts,
    required bool canViewWasteLoss,
    required bool canManageWaste,
    bool loadingProducts = false,
    VoidCallback? onLoadMoreProducts,
  }) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: tr.text('inventory_overview')),
              Tab(text: tr.text('warehouses')),
              Tab(text: tr.text('stock_movements')),
              Tab(text: tr.text('auto_corrections')),
              Tab(text: tr.text('stock_count')),
              Tab(text: tr.text('waste_loss_report')),
              Tab(text: tr.text('unified_batch')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InventoryOverview(
                store: widget.store,
                products: products,
                totalCount: productsTotalCount,
                overview: overview,
                query: query,
                searchController: _searchController,
                onScanBarcode: _scanInventorySearchBarcode,
                onQuery: (value) => setState(() {
                  query = value;
                  _visibleInventoryProductCount = 100;
                }),
                onAdjust: widget.store
                        .hasPermission(AppPermission.inventoryCorrectionsManage)
                    ? _openAdjustmentDialog
                    : null,
                canAdjust: widget.store.hasPermission(
                  AppPermission.inventoryCorrectionsManage,
                ),
                loading: loadingProducts,
                onLoadMore: onLoadMoreProducts,
              ),
              _WarehousesTab(store: widget.store),
              _MovementsList(store: widget.store),
              _AutoCorrectionsTab(store: widget.store),
              _StockCountTab(store: widget.store),
              _WasteLossReportDb(
                store: widget.store,
                canManageWaste: canManageWaste,
              ),
              _InventoryBatchesTab(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAdjustmentDialog(String productId) async {
    final tr = AppLocalizations.of(context);
    final product = widget.store.stockTrackedProducts
        .firstWhere((item) => item.id == productId);
    final qtyController = TextEditingController();
    final notesController = TextEditingController();
    final evidenceController = TextEditingController();
    var selectedWarehouseId = widget.store.resolveWarehouseForPurchase().id;
    var category = 'damage';
    final categories = <String, String>{
      'damage': tr.text('adjustment_damage'),
      'expired': tr.text('adjustment_expired'),
      'free_sample': tr.text('adjustment_free_sample'),
      'internal_consumption': tr.text('adjustment_internal_consumption'),
      'stock_count_shortage': tr.text('adjustment_stock_count_shortage'),
      'stock_count_overage': tr.text('adjustment_stock_count_overage'),
      'other': tr.text('adjustment_other'),
    };
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${tr.text('adjust_stock')} • ${product.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<double>(
                  future: _warehouseStock(product.id, selectedWarehouseId),
                  builder: (context, snapshot) {
                    final currentStock = snapshot.data ??
                        widget.store.stockForWarehouse(
                          product.id,
                          selectedWarehouseId,
                        );
                    return Text(
                      '${tr.text('current_stock')}: ${currentStock.toStringAsFixed(2)}',
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedWarehouseId,
                  decoration: InputDecoration(labelText: tr.text('warehouse')),
                  items: widget.store.warehouses
                      .map((warehouse) => DropdownMenuItem<String>(
                            value: warehouse.id,
                            child: Text(warehouse.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedWarehouseId = widget.store
                          .resolveWarehouseForPurchase(warehouseId: value ?? '')
                          .id;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                      labelText: tr.text('adjustment_reason_type')),
                  items: categories.entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => category = value ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: qtyController,
                    decoration: InputDecoration(
                        labelText: tr.text('quantity_delta'),
                        helperText: tr.text('quantity_delta_help')),
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: notesController,
                    decoration:
                        InputDecoration(labelText: tr.text('notes_optional')),
                    minLines: 1,
                    maxLines: 3),
                const SizedBox(height: 12),
                TextField(
                    controller: evidenceController,
                    decoration: InputDecoration(
                        labelText: tr.text('evidence_optional'),
                        helperText: tr.text('evidence_optional_help'))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () async {
                final delta = double.tryParse(qtyController.text.trim()) ?? 0;
                if (delta == 0) return;
                try {
                  final allocations = product.expiryTrackingEnabled && delta > 0
                      ? await showBatchAllocationDialog(
                          context,
                          product: product,
                          expectedQuantity: delta,
                          sourceId:
                              'adjustment-${DateTime.now().microsecondsSinceEpoch}',
                        )
                      : null;
                  if (product.expiryTrackingEnabled &&
                      delta > 0 &&
                      allocations == null) {
                    return;
                  }
                  await widget.store.adjustStock(
                    productId: productId,
                    warehouseId: selectedWarehouseId,
                    quantityDelta: delta,
                    reason: categories[category] ?? category,
                    adjustmentCategory: category,
                    notes: notesController.text,
                    evidenceRef: evidenceController.text,
                    batchAllocations: allocations ?? const [],
                  );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) setState(() {});
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(localizedErrorText(
                            AppLocalizations.of(context), error))));
                  }
                }
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryProductsResult {
  const _InventoryProductsResult({
    required this.items,
    required this.totalCount,
  });

  final List<Product> items;
  final int totalCount;

  bool get hasMore => items.length < totalCount;
}

class _StockMovementsQueryResult {
  const _StockMovementsQueryResult({
    required this.items,
    required this.totalCount,
  });

  final List<StockMovement> items;
  final int totalCount;

  bool get hasMore => items.length < totalCount;
}

class _InventoryOverview extends StatelessWidget {
  const _InventoryOverview(
      {required this.store,
      required this.products,
      required this.totalCount,
      required this.overview,
      required this.query,
      required this.searchController,
      required this.onScanBarcode,
      required this.onQuery,
      required this.onAdjust,
      required this.canAdjust,
      required this.loading,
      required this.onLoadMore});

  final AppStore store;
  final List<Product> products;
  final int totalCount;
  final _InventoryOverviewMetrics overview;
  final String query;
  final TextEditingController searchController;
  final VoidCallback onScanBarcode;
  final ValueChanged<String> onQuery;
  final ValueChanged<String>? onAdjust;
  final bool canAdjust;
  final bool loading;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final pageInsets = VentioResponsive.pageInsets(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: pageInsets,
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SummaryCard(
                      title: tr.text('product_count'),
                      value: '${overview.productCount}',
                      icon: Icons.inventory_2_outlined),
                  SummaryCard(
                      title: tr.text('total_units'),
                      value: '${overview.totalUnits}',
                      icon: Icons.layers_outlined),
                  SummaryCard(
                      title: tr.text('low_stock_alerts'),
                      value: '${overview.lowStockCount}',
                      icon: Icons.warning_amber_rounded),
                  SummaryCard(
                      title: tr.text('inventory_value'),
                      value: formatUsdReferenceAmount(
                          overview.inventoryRetailValue, store.storeProfile),
                      icon: Icons.payments_outlined),
                  SummaryCard(
                      title: tr.text('pending_auto_corrections'),
                      value: '${overview.pendingAutoCorrectionCount}',
                      icon: Icons.notifications_active_outlined),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: tr.text('search_inventory'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: tr.text('scan_with_camera'),
                    onPressed: onScanBarcode,
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                ),
                onChanged: onQuery,
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(tr.text('inventory_overview'),
                          style: Theme.of(context).textTheme.titleMedium),
                      subtitle: Text(tr.text('inventory_page_desc')),
                      trailing: PageDataLoadIndicator(
                        loadedCount: products.length,
                        totalCount: totalCount,
                      ),
                    ),
                    const Divider(height: 1),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      )
                    else if (products.isEmpty)
                      Padding(
                          padding: VentioResponsive.pageInsets(context),
                          child: Text(tr.text('no_inventory_items'))),
                  ],
                ),
              ),
            ]),
          ),
        ),
        if (products.isNotEmpty)
          SliverPadding(
            padding: EdgeInsetsDirectional.only(
              start: pageInsets.left,
              end: pageInsets.right,
              bottom: pageInsets.bottom,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.crossAxisExtent < 620;
                return SliverFixedExtentList(
                  itemExtent: compact ? 128 : 82,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = products[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Card(
                          margin: EdgeInsets.zero,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                          child: _InventoryProductTile(
                            product: product,
                            store: store,
                            compact: compact,
                            canAdjust: canAdjust,
                            onAdjust: onAdjust,
                          ),
                        ),
                      );
                    },
                    childCount: products.length,
                  ),
                );
              },
            ),
          ),
        if (onLoadMore != null)
          SliverPadding(
            padding: EdgeInsetsDirectional.only(
              start: pageInsets.left,
              end: pageInsets.right,
              bottom: pageInsets.bottom,
            ),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: TextButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    '${tr.text('more')} (${products.length}/$totalCount)',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InventoryProductTile extends StatelessWidget {
  const _InventoryProductTile(
      {required this.product,
      required this.store,
      required this.compact,
      required this.onAdjust,
      required this.canAdjust});

  final Product product;
  final AppStore store;
  final bool compact;
  final ValueChanged<String>? onAdjust;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isLow =
        product.trackStock && product.stock <= product.lowStockThreshold;
    final meta = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(formatUsdReferenceAmount(product.price, store.storeProfile)),
        Chip(
            avatar: isLow ? const Icon(Icons.priority_high, size: 16) : null,
            label: Text('${tr.text('stock')}: ${product.stock}')),
        if (canAdjust)
          TextButton.icon(
              onPressed: onAdjust == null ? null : () => onAdjust!(product.id),
              icon: const Icon(Icons.tune),
              label: Text(tr.text('adjust'))),
      ],
    );
    if (compact) {
      return ListTile(
        leading: CircleAvatar(
            child: Icon(isLow
                ? Icons.warning_amber_rounded
                : Icons.inventory_2_outlined)),
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.code} • ${product.category}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            meta,
          ],
        ),
      );
    }
    return ListTile(
      leading: CircleAvatar(
          child: Icon(isLow
              ? Icons.warning_amber_rounded
              : Icons.inventory_2_outlined)),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.code} • ${product.category}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: VentioResponsive.clampToScreen(context, 360,
                min: 180, horizontalPadding: 120)),
        child: Align(alignment: AlignmentDirectional.centerEnd, child: meta),
      ),
    );
  }
}

List<Product> _filterProducts(List<Product> products, String query) {
  final value = query.trim().toLowerCase();
  if (value.isEmpty) return products;
  return products.where((item) {
    return item.name.toLowerCase().contains(value) ||
        item.code.toLowerCase().contains(value) ||
        item.barcode.toLowerCase().contains(value) ||
        item.category.toLowerCase().contains(value) ||
        item.effectiveSaleUnits
            .any((unit) => unit.barcode.toLowerCase().contains(value)) ||
        item.effectivePurchaseUnits
            .any((unit) => unit.barcode.toLowerCase().contains(value));
  }).toList(growable: false);
}

class _WarehousesTab extends StatefulWidget {
  const _WarehousesTab({required this.store});
  final AppStore store;

  @override
  State<_WarehousesTab> createState() => _WarehousesTabState();
}
