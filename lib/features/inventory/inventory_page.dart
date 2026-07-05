import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/business_revision_service.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/local_database_service.dart';
import '../../core/storage/sqlite/business_sqlite_store.dart' show BusinessQueryPage;
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/revision_cache.dart';
import '../../core/services/page_timing_scope.dart';
import '../../data/app_store.dart';
import '../../models/inventory_count.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../models/user_role.dart';
import '../../models/warehouse.dart';
import '../../widgets/page_data_load_indicator.dart';
import '../../widgets/summary_card.dart';
import '../barcode/barcode_scanner_page.dart';

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
    case 'warehouse_transfer_in':
      return tr.text('warehouse_transfer_in');
    case 'warehouse_transfer_out':
      return tr.text('warehouse_transfer_out');
    case 'count_adjustment':
      return tr.text('count_adjustment');
    case 'manufacturing_consume':
      return tr.text('manufacturing_consume');
    case 'manufacturing_output':
      return tr.text('manufacturing_output');
    default:
      return type.replaceAll('_', ' ');
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});

  final AppStore store;

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

  factory _InventoryOverviewMetrics.fromSummary(Map<String, Object?> summary) {
    return _InventoryOverviewMetrics(
      productCount: (summary['productCount'] as num?)?.toInt() ?? 0,
      totalUnits: (summary['totalUnits'] as num?)?.toDouble() ?? 0,
      lowStockCount: (summary['lowStockCount'] as num?)?.toInt() ?? 0,
      inventoryRetailValue:
          (summary['inventoryRetailValue'] as num?)?.toDouble() ?? 0,
      pendingAutoCorrectionCount:
          (summary['pendingAutoCorrectionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

_InventoryOverviewMetrics _emptyInventoryOverviewMetrics() =>
    const _InventoryOverviewMetrics(
      productCount: 0,
      totalUnits: 0,
      lowStockCount: 0,
      inventoryRetailValue: 0,
      pendingAutoCorrectionCount: 0,
    );

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  String query = '';
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController =
      TabController(length: 6, vsync: this);
  Future<_InventoryProductsResult?>? _inventoryProductsFuture;
  String _inventoryProductsFutureKey = '';
  Future<_InventoryOverviewMetrics?>? _inventoryOverviewFuture;
  int _inventoryOverviewFutureKey = -1;
  int _visibleInventoryProductCount = 100;

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
      _inventoryOverviewFuture = null;
      _inventoryOverviewFutureKey = -1;
      _visibleInventoryProductCount = 100;
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
        message: 'This section is not available for your current role.',
      );
    }
    if (!widget.store.isCoreDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final normalizedQuery = query.trim().toLowerCase();
    final canViewOverview =
        widget.store.hasPermission(AppPermission.inventoryView) ||
            widget.store.hasPermission(AppPermission.reportsView) ||
            widget.store.hasPermission(AppPermission.productsCreate) ||
            widget.store.hasPermission(AppPermission.productsEdit) ||
            widget.store.hasPermission(AppPermission.productsDelete);
    final canManageWarehouses = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWarehousesManage,
      AppPermission.productsEdit,
    });
    final canViewMovements = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });
    final canViewCorrections = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });
    final canManageCounts = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCountsManage,
      AppPermission.productsEdit,
    });
    final canViewWasteLoss = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    });

    if (!canViewOverview &&
        !canManageWarehouses &&
        !canViewMovements &&
        !canViewCorrections &&
        !canManageCounts &&
        !canViewWasteLoss) {
      return _InventoryAccessDenied(
        title: tr.text('inventory'),
        message: 'This section is not available for your current role.',
      );
    }

    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder<_InventoryOverviewMetrics?>(
      future: _queryInventoryOverviewFromSqlite(),
      builder: (context, overviewSnapshot) {
        final currentOverview =
            overviewSnapshot.data ?? _emptyInventoryOverviewMetrics();
        return FutureBuilder<_InventoryProductsResult?>(
          future: _queryInventoryProductsFromSqlite(normalizedQuery),
          builder: (context, snapshot) {
            final result = snapshot.data;
            if (result != null && !snapshot.hasError) {
              return _buildInventoryShell(
                tr,
                products: result.items,
                productsTotalCount: result.totalCount,
                overview: currentOverview,
                canManageWarehouses: canManageWarehouses,
                canViewMovements: canViewMovements,
                canViewCorrections: canViewCorrections,
                canManageCounts: canManageCounts,
                canViewWasteLoss: canViewWasteLoss,
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
                overview: currentOverview,
                canManageWarehouses: canManageWarehouses,
                canViewMovements: canViewMovements,
                canViewCorrections: canViewCorrections,
                canManageCounts: canManageCounts,
                canViewWasteLoss: canViewWasteLoss,
                loadingProducts: true,
              );
            }
            return _buildInventoryShell(
              tr,
              products: const <Product>[],
              productsTotalCount: 0,
              overview: currentOverview,
              canManageWarehouses: canManageWarehouses,
              canViewMovements: canViewMovements,
              canViewCorrections: canViewCorrections,
              canManageCounts: canManageCounts,
              canViewWasteLoss: canViewWasteLoss,
              loadingProducts: false,
            );
          },
        );
      },
    );
  }

  Future<_InventoryOverviewMetrics?> _queryInventoryOverviewFromSqlite() {
    final key = BusinessRevisionService.instance.inventoryRevision;
    if (_inventoryOverviewFuture == null || _inventoryOverviewFutureKey != key) {
      _inventoryOverviewFutureKey = key;
      _inventoryOverviewFuture = () async {
        final summary = await InventoryRepository.buildOverview();
        if (summary == null) return null;
        return _InventoryOverviewMetrics.fromSummary(summary);
      }();
    }
    return _inventoryOverviewFuture!;
  }

  Future<_InventoryProductsResult?> _queryInventoryProductsFromSqlite(
    String normalizedQuery,
  ) {
    final limit = _visibleInventoryProductCount.clamp(1, 500).toInt();
    final key =
        '${BusinessRevisionService.instance.inventoryRevision}|$normalizedQuery|$limit';
    if (_inventoryProductsFuture == null ||
        _inventoryProductsFutureKey != key) {
      _inventoryProductsFutureKey = key;
      _inventoryProductsFuture = () async {
        final page = await ProductRepository.queryPage(
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
                onAdjust: canManageCounts ? _openAdjustmentDialog : null,
                canAdjust: canManageCounts,
                loading: loadingProducts,
                onLoadMore: onLoadMoreProducts,
              ),
              _WarehousesTab(store: widget.store),
              _MovementsList(store: widget.store),
              _AutoCorrectionsTab(store: widget.store),
              _StockCountTab(store: widget.store),
              _WasteLossReport(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAdjustmentDialog(String productId) async {
    final tr = AppLocalizations.of(context);
    final product = await ProductRepository.getById(productId);
    if (product == null) return;
    if (!mounted) return;
    final qtyController = TextEditingController();
    final notesController = TextEditingController();
    final evidenceController = TextEditingController();
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
          title: Text('${tr.text('adjust_stock')} â€¢ ${product.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${tr.text('current_stock')}: ${product.stock}'),
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
                  await InventoryRepository.adjustStock(context: 
                    widget.store,
                    productId: productId,
                    quantityDelta: delta,
                    reason: categories[category] ?? category,
                    adjustmentCategory: category,
                    notes: notesController.text,
                    evidenceRef: evidenceController.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) setState(() {});
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())));
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
            Text('${product.code} â€¢ ${product.category}',
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
      subtitle: Text('${product.code} â€¢ ${product.category}',
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

class _WarehousesTab extends StatefulWidget {
  const _WarehousesTab({required this.store});
  final AppStore store;

  @override
  State<_WarehousesTab> createState() => _WarehousesTabState();
}

class _WarehousesTabState extends State<_WarehousesTab> {
  final RevisionKeyCache<Map<String, List<_WarehouseProductStock>>>
      _stockRowsCache =
      RevisionKeyCache<Map<String, List<_WarehouseProductStock>>>();

  @override
  void didUpdateWidget(covariant _WarehousesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _stockRowsCache.invalidate();
    }
  }

  Map<String, List<_WarehouseProductStock>> _stockRowsByWarehouse() {
    return _stockRowsCache.getOrCompute(
      BusinessRevisionService.instance.inventoryRevision,
      widget.store.appIdentity.storeId,
      () {
        return <String, List<_WarehouseProductStock>>{};
      },
    );
  }

  Future<void> _createWarehouse() async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final locationController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('create_warehouse')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: tr.text('warehouse_name'))),
            const SizedBox(height: 12),
            TextField(
                controller: codeController,
                decoration:
                    InputDecoration(labelText: tr.text('code_optional'))),
            const SizedBox(height: 12),
            TextField(
                controller: locationController,
                decoration:
                    InputDecoration(labelText: tr.text('location_optional'))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                await InventoryRepository.createWarehouse(context: 
                  widget.store,
                  name: nameController.text,
                  code: codeController.text,
                  location: locationController.text,
                );
                if (context.mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _transferStock() async {
    final tr = AppLocalizations.of(context);
    final products = const <Product>[];
    final warehouses = const <Warehouse>[];
    if (products.isEmpty || warehouses.length < 2) return;
    var productId = products.first.id;
    var fromWarehouseId = warehouses.first.id;
    var toWarehouseId =
        warehouses.length > 1 ? warehouses[1].id : warehouses.first.id;
    final qtyController = TextEditingController();
    final notesController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('transfer_stock')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: productId,
                decoration: InputDecoration(labelText: tr.text('product')),
                items: products
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => productId = value ?? productId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: fromWarehouseId,
                decoration:
                    InputDecoration(labelText: tr.text('from_warehouse')),
                items: warehouses
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) => setDialogState(
                    () => fromWarehouseId = value ?? fromWarehouseId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: toWarehouseId,
                decoration: InputDecoration(labelText: tr.text('to_warehouse')),
                items: warehouses
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) => setDialogState(
                    () => toWarehouseId = value ?? toWarehouseId),
              ),
              const SizedBox(height: 12),
              Text('${tr.text('available')}: 0'),
              const SizedBox(height: 12),
              TextField(
                  controller: qtyController,
                  decoration: InputDecoration(labelText: tr.text('quantity')),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: notesController,
                  decoration:
                      InputDecoration(labelText: tr.text('notes_optional'))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () async {
                try {
                  await InventoryRepository.transferStock(context: 
                    widget.store,
                    productId: productId,
                    fromWarehouseId: fromWarehouseId,
                    toWarehouseId: toWarehouseId,
                    quantity: double.tryParse(qtyController.text.trim()) ?? 0,
                    notes: notesController.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) setState(() {});
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())));
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

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryWarehousesManage,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Warehouses',
        message: 'Warehouse management is not available for your current role.',
      );
    }
    final warehouses = const <Warehouse>[];
    final stockRowsByWarehouse = _stockRowsByWarehouse();
    return ListView.builder(
      padding: VentioResponsive.pageInsets(context),
      itemCount: warehouses.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                  onPressed: _createWarehouse,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(tr.text('create_warehouse'))),
              OutlinedButton.icon(
                  onPressed: warehouses.length < 2 ? null : _transferStock,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(tr.text('transfer_stock'))),
            ]),
          );
        }
        final warehouse = warehouses[index - 1];
        final rows = stockRowsByWarehouse[warehouse.id] ??
            const <_WarehouseProductStock>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
            title: Text(warehouse.name),
            subtitle: Text([
              if (warehouse.code.isNotEmpty) warehouse.code,
              if (warehouse.location.isNotEmpty) warehouse.location
            ].join(' â€¢ ')),
            children: [
              for (final row in rows.take(100))
                ListTile(
                  dense: true,
                  title: Text(row.product.name),
                  trailing: Text('${row.stock}'),
                ),
              if (rows.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr.text('no_inventory_items'))),
            ],
          ),
        );
      },
    );
  }
}

class _WarehouseProductStock {
  const _WarehouseProductStock({required this.product, required this.stock});

  final Product product;
  final double stock;
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!store.hasAnyPermission(<String>{
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Stock movements',
        message:
            'Stock movement history is not available for your current role.',
      );
    }
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder<BusinessQueryPage<StockMovement>?>(
      future: InventoryRepository.queryStockMovements(limit: 200),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return _buildMovementsList(
          context,
          tr,
          snapshot.data?.items ?? const <StockMovement>[],
        );
      },
    );
  }

  Widget _buildMovementsList(
    BuildContext context,
    AppLocalizations tr,
    List<StockMovement> movements,
  ) {
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Card(
          child: movements.isEmpty
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
                            "${_movementTypeLabel(tr, movement.type)} â€¢ ${movement.warehouseName} â€¢ ${movement.referenceNo} â€¢ ${movement.date.toLocal().toString().split('.').first}\n${movement.reason}${movement.notes.isNotEmpty ? ' â€¢ ${movement.notes}' : ''}${movement.evidenceRef.isNotEmpty ? ' â€¢ ${tr.text('evidence')}: ${movement.evidenceRef}' : ''}"),
                        isThreeLine: true,
                        trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  movement.quantity > 0
                                      ? '+${movement.quantity}'
                                      : '${movement.quantity}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (movement.unitCost > 0)
                                Text(formatUsdReferenceAmount(
                                    movement.value, store.storeProfile)),
                            ]),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
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

class _AutoCorrectionsTabState extends State<_AutoCorrectionsTab> {
  bool showReviewed = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canReview = widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.productsEdit,
    });
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCorrectionsManage,
      AppPermission.inventoryMovementsView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Auto corrections',
        message:
            'Auto correction review is not available for your current role.',
      );
    }
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder<BusinessQueryPage<StockMovement>?>(
      future: InventoryRepository.queryStockMovements(
        movementType: 'auto_correction',
        limit: 500,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final allCorrections = snapshot.data?.items ?? const <StockMovement>[];
        final pending = allCorrections
            .where((movement) => !movement.isReviewed)
            .toList(growable: false);
        final corrections = showReviewed ? allCorrections : pending;
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
                    value: '${pending.length}',
                    icon: Icons.notifications_active_outlined),
                SummaryCard(
                    title: tr.text('auto_corrections'),
                    value: '${allCorrections.length}',
                    icon: Icons.inventory_outlined),
                SummaryCard(
                    title: tr.text('quantity'),
                    value: totalQty.toStringAsFixed(
                        totalQty.truncateToDouble() == totalQty ? 0 : 2),
                    icon: Icons.add_box_outlined),
                SummaryCard(
                    title: tr.text('estimated_value'),
                    value: formatUsdReferenceAmount(
                        totalValue, widget.store.storeProfile),
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
          ],
        );
      },
    );
  }

  Future<void> _reviewMovement(String id) async {
    final tr = AppLocalizations.of(context);
    try {
      await InventoryRepository.reviewAutoCorrection(widget.store, id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr.text('auto_correction_marked_reviewed'))));
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _StockCountTab extends StatefulWidget {
  const _StockCountTab({required this.store});

  final AppStore store;

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

  @override
  void didUpdateWidget(covariant _StockCountTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _productsCache.invalidate();
      _lineLookupCache.invalidate();
      _movementCountCache.invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.inventoryCountsManage,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Stock count',
        message: 'Stock count actions are not available for your current role.',
      );
    }
    return FutureBuilder<List<InventoryCountSession>?>(
      future: InventoryRepository.getInventoryCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final sessions = snapshot.data ?? const <InventoryCountSession>[];
        InventoryCountSession? active;
        for (final session in sessions.reversed) {
          if (session.isOpen) {
            active = session;
            break;
          }
        }
        final currentActive = active;
        final lineLookup = _lineLookupCache.getOrCompute(
          BusinessRevisionService.instance.inventoryRevision,
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
        final movementCounts = _movementCountCache.getOrCompute(
          BusinessRevisionService.instance.inventoryRevision,
          active?.id ?? 'no_active',
          () {
            final counts = <String, int>{};
            if (active != null) {
              final countedAtByProduct = <String, DateTime>{};
              for (final line in active.lines) {
                final countedAt = line.countedAt;
                if (countedAt == null) continue;
                countedAtByProduct[line.productId] = countedAt;
                counts[line.productId] = 0;
              }
              if (countedAtByProduct.isNotEmpty) {
                for (final movement in const <StockMovement>[]) {
                  final countedAt = countedAtByProduct[movement.productId];
                  if (countedAt == null) continue;
                  if (movement.type == 'count_adjustment' ||
                      !movement.date.isAfter(countedAt)) {
                    continue;
                  }
                  counts[movement.productId] =
                      (counts[movement.productId] ?? 0) + 1;
                }
              }
            }
            return counts;
          },
        );
        final needle = query.trim().toLowerCase();
        final products = _productsCache.getOrCompute(
      BusinessRevisionService.instance.inventoryRevision,
          '${active?.id ?? 'no_active'}|$needle',
          () => const <Product>[],
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
                    if (currentActive != null) ...[
                      FilledButton.icon(
                        onPressed: currentActive.countedLines == 0
                            ? null
                            : () => _approveCount(currentActive.id),
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(tr.text('approve_stock_count')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _cancelCount(currentActive.id),
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
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_outlined)),
                  title: Text(
                      '${tr.text('active_stock_count')} â€¢ ${active.countNo}'),
                  subtitle: Text(
                      '${tr.text('started_at')}: ${active.createdAt.toLocal().toString().split('.').first}'),
                ),
                const Divider(height: 1),
                for (final product in products.take(200))
                  _StockCountProductTile(
                      sessionId: currentActive?.id,
                      product: product,
                      line: lineLookup[product.id],
                      movementsAfter: movementCounts[product.id] ?? 0),
              ],
            ),
          ),
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
                        : session.isOpen
                            ? Icons.pending_actions_outlined
                            : Icons.cancel_outlined),
                    title: Text(session.countNo),
                    subtitle: Text(
                        '${tr.text('status')}: ${session.status} â€¢ ${tr.text('counted_products')}: ${session.countedLines}/${session.totalLines}'),
                    trailing: Text(session.createdAt
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first),
                  ),
            ],
          ),
        ),
          ],
        );
      },
    );
  }

  Future<void> _startCount() async {
    try {
      await InventoryRepository.createInventoryCountSession();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _approveCount(String id) async {
    try {
      await InventoryRepository.approveInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _cancelCount(String id) async {
    try {
      await InventoryRepository.cancelInventoryCount(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _StockCountProductTile extends StatelessWidget {
  const _StockCountProductTile(
      {required this.sessionId,
      required this.product,
      required this.line,
      required this.movementsAfter});

  final String? sessionId;
  final Product product;
  final InventoryCountLine? line;
  final int movementsAfter;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return ListTile(
      title: Text(product.name),
      subtitle: Text([
        '${tr.text('system_stock')}: ${product.stock}',
        if (line?.isCounted == true)
          '${tr.text('counted')}: ${line!.countedQty}',
        if (line?.countedAt != null)
          '${tr.text('counted_at')}: ${line!.countedAt!.toLocal().toString().split('.').first}',
        if (movementsAfter > 0)
          'âš  ${tr.text('movements_after_count')}: $movementsAfter',
      ].join(' â€¢ ')),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: () => _enterCount(context),
        child: Text(
            line?.isCounted == true ? tr.text('recount') : tr.text('count')),
      ),
    );
  }

  Future<void> _enterCount(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tr.text('count')} â€¢ ${product.name}'),
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
      final activeSessionId = sessionId;
      if (activeSessionId == null) return;
      await InventoryRepository.countInventoryLine(
        sessionId: activeSessionId,
        productId: product.id,
        countedQty: value,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _WasteLossReport extends StatelessWidget {
  const _WasteLossReport({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!store.hasAnyPermission(<String>{
      AppPermission.inventoryWasteView,
      AppPermission.reportsView,
      AppPermission.productsEdit,
    })) {
      return const _InventorySectionDenied(
        title: 'Waste loss report',
        message:
            'Waste and loss reporting is not available for your current role.',
      );
    }
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder<BusinessQueryPage<StockMovement>?>(
      future: InventoryRepository.queryStockMovements(
        lossOnly: true,
        limit: 500,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return _buildLossLossReport(
          context,
          tr,
          snapshot.data?.items ?? const <StockMovement>[],
        );
      },
    );
  }

  Widget _buildLossLossReport(
    BuildContext context,
    AppLocalizations tr,
    List<StockMovement> lossMovements,
  ) {
    final totals = <String, _WasteTotal>{};
    double totalValue = 0;
    double totalQty = 0;
    for (final movement in lossMovements) {
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
    return _buildLossSummary(
      context,
      tr,
      lossMovements,
      totals,
      totalQty,
      totalValue,
    );
  }

  Widget _buildLossSummary(
    BuildContext context,
    AppLocalizations tr,
    List<StockMovement> lossMovements,
    Map<String, _WasteTotal> totals,
    double totalQty,
    double totalValue,
  ) {
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(
                title: tr.text('loss_movements'),
                value: '${lossMovements.length}',
                icon: Icons.report_problem_outlined),
            SummaryCard(
                title: tr.text('loss_quantity'),
                value: totalQty.toStringAsFixed(
                    totalQty.truncateToDouble() == totalQty ? 0 : 2),
                icon: Icons.remove_circle_outline),
            SummaryCard(
                title: tr.text('loss_value'),
                value: formatUsdReferenceAmount(totalValue, store.storeProfile),
                icon: Icons.money_off_outlined),
          ],
        ),
        const SizedBox(height: 20),
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
                            '${tr.text('movements')}: ${entry.value.count} â€¢ ${tr.text('quantity')}: ${entry.value.quantity}'),
                        trailing: Text(formatUsdReferenceAmount(
                            entry.value.value, store.storeProfile)),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
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

