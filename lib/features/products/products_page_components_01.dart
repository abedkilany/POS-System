part of 'products_page.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store});

  final ApplicationSession store;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String query = '';
  String categoryFilter = 'All';
  final Set<String> _priceListViews = <String>{};
  final Set<String> _selectedProductIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _productRevealTimer;
  int _visibleProductCount = 100;
  int _productRevealTargetCount = 0;
  int _cachedRevision = -1;
  List<Product>? _cachedProductSource;
  List<Product>? _cachedCategorySource;
  String _cachedQuery = '';
  String _cachedCategoryFilter = 'All';
  List<Product> _cachedFilteredProducts = const <Product>[];
  List<String> _cachedCategories = const <String>[];
  Future<_ProductsQueryResult?>? _productsQueryFuture;
  String _productsQueryFutureKey = '';
  final Map<String, _RowCacheEntry> _rowCache = <String, _RowCacheEntry>{};
  final Map<String, String> _searchIndexCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    unawaited(_refreshPricingData());
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _productRevealTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _cachedRevision = -1;
      _cachedProductSource = null;
      _cachedCategorySource = null;
      _cachedQuery = '';
      _cachedCategoryFilter = 'All';
      _cachedFilteredProducts = const <Product>[];
      _cachedCategories = const <String>[];
      _productsQueryFuture = null;
      _productsQueryFutureKey = '';
      _rowCache.clear();
      _searchIndexCache.clear();
      _resetProductReveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.canViewProducts) {
      return _PermissionDeniedScaffold(
        title: tr.text('products'),
        message:
            'This page is available in read-only mode only for users who can access product data.',
      );
    }
    if (!widget.store.runtime.isCoreDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final value = query.trim().toLowerCase();
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_ProductsQueryResult?>(
        future: _queryProductsFromSqlite(value),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildProductsView(
              context,
              tr,
              localeTag: localeTag,
              products: result.items,
              totalCount: result.totalCount,
              categories: result.categories,
              costSnapshots: result.costSnapshots,
              loading: snapshot.connectionState == ConnectionState.waiting &&
                  result.items.isEmpty,
              onLoadMore: result.hasMore
                  ? () => _loadMoreProducts(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildProductsView(
              context,
              tr,
              localeTag: localeTag,
              products: const <Product>[],
              totalCount: 0,
              categories: const <String>['All'],
              loading: true,
            );
          }
          return _buildProductsFromMemory(context, tr, localeTag);
        },
      );
    }
    return _buildProductsFromMemory(context, tr, localeTag);
  }
}

class _PriceListFieldOption {
  const _PriceListFieldOption({
    required this.id,
    required this.labelAr,
    required this.labelEn,
  });

  final String id;
  final String labelAr;
  final String labelEn;
}

class _ProductsQueryResult {
  const _ProductsQueryResult({
    required this.items,
    required this.totalCount,
    required this.categories,
    this.costSnapshots = const <String, ProductCostSnapshot>{},
  });

  final List<Product> items;
  final int totalCount;
  final List<String> categories;
  final Map<String, ProductCostSnapshot> costSnapshots;

  bool get hasMore => items.length < totalCount;
}

class _PermissionDeniedScaffold extends StatelessWidget {
  const _PermissionDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
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

class _ProductSelectionBar extends StatelessWidget {
  const _ProductSelectionBar({
    required this.selectedCount,
    required this.visibleCount,
    required this.allVisibleSelected,
    required this.someVisibleSelected,
    required this.onToggleVisible,
    required this.onClear,
  });

  final int selectedCount;
  final int visibleCount;
  final bool allVisibleSelected;
  final bool someVisibleSelected;
  final ValueChanged<bool> onToggleVisible;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              value: allVisibleSelected
                  ? true
                  : (someVisibleSelected ? null : false),
              onChanged: (_) => onToggleVisible(!allVisibleSelected),
            ),
            Expanded(
              child: Text(
                isArabic
                    ? 'تحديد المعروض ($visibleCount) • المحدد: $selectedCount'
                    : 'Select displayed ($visibleCount) • Selected: $selectedCount',
              ),
            ),
            if (selectedCount > 0)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: Text(isArabic ? 'إلغاء التحديد' : 'Clear selection'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.row,
    required this.compact,
    this.selected = false,
    this.onSelectedChanged,
    this.onEdit,
    this.onDelete,
    this.onHistory,
  });

  final _ProductRowData row;
  final bool compact;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final product = row.product;
    final historyButton = IconButton(
      onPressed: onHistory,
      icon: const Icon(Icons.history_outlined),
      tooltip: Localizations.localeOf(context).languageCode == 'ar'
          ? 'سجل الأسعار'
          : 'Price history',
    );
    return Card(
      child: compact
          ? Padding(
              padding: VentioResponsive.cardInsets(context),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onSelectedChanged != null)
                    Checkbox(value: selected, onChanged: onSelectedChanged),
                  CircleAvatar(
                      child: Icon(product.isActive
                          ? Icons.inventory_2_outlined
                          : Icons.block_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        if (row.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(row.subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 8),
                        Text(row.meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge),
                        if (row.purchaseMeta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(row.purchaseMeta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const Spacer(),
                        Row(
                          children: [
                            historyButton,
                            IconButton(
                                onPressed: onEdit,
                                icon: const Icon(Icons.edit_outlined),
                                tooltip:
                                    AppLocalizations.of(context).text('edit')),
                            IconButton(
                                onPressed: onDelete,
                                icon: const Icon(Icons.delete_outline),
                                tooltip: AppLocalizations.of(context)
                                    .text('delete')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSelectedChanged != null)
                    Checkbox(value: selected, onChanged: onSelectedChanged),
                  CircleAvatar(
                      child: Icon(product.isActive
                          ? Icons.inventory_2_outlined
                          : Icons.block_outlined)),
                ],
              ),
              title: Text(product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  [row.subtitle, row.purchaseMeta]
                      .where((item) => item.trim().isNotEmpty)
                      .join('\n'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Text(row.meta),
                  ),
                  historyButton,
                  IconButton(
                      onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline)),
                ],
              ),
            ),
    );
  }
}

class _ProductRowData {
  const _ProductRowData({
    required this.product,
    required this.subtitle,
    required this.meta,
    required this.purchaseMeta,
  });

  final Product product;
  final String subtitle;
  final String meta;
  final String purchaseMeta;

  factory _ProductRowData.fromStore(
    Product product,
    ApplicationSession store,
    StoreProfile storeProfile,
    AppLocalizations tr, {
    ProductCostSnapshot? costSnapshot,
  }) {
    final subtitle = [
      product.code,
      product.barcode,
      product.category,
      product.brand
    ].where((e) => e.trim().isNotEmpty).join(' • ');
    final compatibilityCost = store.catalog.productCostFor(product.id);
    final fallbackReference =
        product.usdCost > 0 ? product.usdCost : product.cost;
    final snapshot = costSnapshot ??
        ProductCostSnapshot(
          productId: product.id,
          currentInventoryUnitCost: compatibilityCost.averageCost > 0
              ? compatibilityCost.averageCost
              : fallbackReference,
          inventoryQuantity: product.trackStock ? product.stock : 0,
          batchCount: 0,
          lastPurchaseUnitCost: store.commerce.lastPurchasePriceForProduct(product.id),
          referenceUnitCost: fallbackReference,
        );
    final supplierCount = store.commerce.supplierCountForProduct(product.id);
    final displayPrice = store.catalog.defaultProductUsdPrice(product);
    final meta = product.trackStock
        ? '${product.stock} ${product.unit} • ${formatUsdReferenceAmount(displayPrice, storeProfile)}'
        : '${tr.text('quantity_type_service')} • ${formatUsdReferenceAmount(displayPrice, storeProfile)}';
    final purchaseMeta = [
      if (product.trackStock && snapshot.hasInventory)
        '${tr.text('current_inventory_cost')}: ${formatUsdReferenceAmount(snapshot.currentInventoryUnitCost, storeProfile)}${snapshot.batchCount > 0 ? ' (${snapshot.batchCount} ${tr.text('batches_label')})' : ''}',
      if (snapshot.lastPurchaseUnitCost != null)
        '${tr.text('last_purchase_cost_label')}: ${formatUsdReferenceAmount(snapshot.lastPurchaseUnitCost!, storeProfile)}',
      if (snapshot.referenceUnitCost > 0)
        '${tr.text('reference_cost')}: ${formatUsdReferenceAmount(snapshot.referenceUnitCost, storeProfile)}',
      if (supplierCount > 0)
        tr.format('suppliers_count', {'count': supplierCount}),
    ].join(' • ');
    return _ProductRowData(
        product: product,
        subtitle: subtitle,
        meta: meta,
        purchaseMeta: purchaseMeta);
  }
}

class _RowCacheEntry {
  const _RowCacheEntry(this.signature, this.row);

  final String signature;
  final _ProductRowData row;
}

class _ProductFormResult {
  const _ProductFormResult(
      {required this.product,
      required this.addToQuickProducts,
      this.supplierPriceSave,
      this.priceSave});

  final Product product;
  final bool addToQuickProducts;
  final Future<void> Function()? supplierPriceSave;
  final Future<void> Function()? priceSave;
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.store, this.product});

  final ApplicationSession store;
  final Product? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}
