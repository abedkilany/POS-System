// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/revision_cache.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/purchase_pdf_service.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../data/app_store.dart';
import '../../widgets/page_data_load_indicator.dart';
import '../../widgets/shortcut_key_picker.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/inventory_batch.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/user_role.dart';
import '../barcode/barcode_scanner_page.dart';
import '../security/sensitive_action_guard.dart';

part 'purchases_page_dialog_actions_01.dart';
part 'purchases_page_dialog_actions_02.dart';
part 'purchases_page_dialog_ui.dart';

part 'purchases_page_methods_01.dart';
part 'purchases_page_methods_02.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _pageShortcutFocusNode = FocusNode();
  String _statusFilter = 'all';
  String _sortMode = 'newest';
  Timer? _purchaseRevealTimer;
  int _visiblePurchaseCount = 100;
  int _purchaseRevealTargetCount = 0;
  Future<_PurchaseQueryResult?>? _purchaseQueryFuture;
  String _purchaseQueryFutureKey = '';
  Future<Map<String, Object?>?>? _purchaseOverviewFuture;
  String _purchaseOverviewFutureKey = '';
  final RevisionKeyCache<List<Purchase>> _filteredPurchasesCache =
      RevisionKeyCache<List<Purchase>>();
  late Future<void> _dataFuture;

  @override
  void didUpdateWidget(covariant PurchasesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _purchaseQueryFuture = null;
      _purchaseQueryFutureKey = '';
      _purchaseOverviewFuture = null;
      _purchaseOverviewFutureKey = '';
      _filteredPurchasesCache.invalidate();
      _resetPurchaseReveal();
      _dataFuture = widget.store.commerce.ensurePurchasesLoaded();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    _dataFuture = widget.store.commerce.ensurePurchasesLoaded();
    HardwareKeyboard.instance.addHandler(_handlePurchasesHardwareShortcutKey);
  }

  @override
  void dispose() {
    _purchaseRevealTimer?.cancel();
    widget.store.removeListener(_handleStoreChanged);
    HardwareKeyboard.instance
        .removeHandler(_handlePurchasesHardwareShortcutKey);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageShortcutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewPurchases) {
      return _AccessDeniedScaffold(
        title: tr.text('purchases'),
        message: tr.text('no_access_purchase_records'),
      );
    }
    final normalizedQuery = _searchController.text.trim().toLowerCase();
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_PurchaseQueryResult?>(
        future: _queryPurchasesFromSqlite(normalizedQuery),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildPurchasesSqliteView(
              context,
              tr,
              result,
              normalizedQuery,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return Center(child: Text(tr.text('no_purchases_yet')));
        },
      );
    }
    return FutureBuilder<void>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final allPurchases = widget.store.purchases;
        final overview = widget.store.purchasesOverview;
        final monthlyTotal = overview.monthlyTotal;
        final monthlyCount = overview.monthlyCount;
        final draftTotal = overview.draftTotal;
        final query = _searchController.text.trim().toLowerCase();
        final useDefaultView =
            query.isEmpty && _statusFilter == 'all' && _sortMode == 'newest';
        final purchases = useDefaultView
            ? allPurchases
            : _filteredPurchasesCache.getOrCompute(
                widget.store.purchasesRevision,
                '$_statusFilter|$_sortMode|$query',
                () {
                  final filtered = allPurchases.where((p) {
                    final matchesSearch =
                        query.isEmpty || p.searchText.contains(query);
                    final matchesStatus = _statusFilter == 'all' ||
                        (_statusFilter == 'draft' &&
                            !p.isReceived &&
                            !p.isCancelled) ||
                        (_statusFilter == 'received' &&
                            p.isReceived &&
                            !p.isReturned) ||
                        (_statusFilter == 'returned' && p.isReturned) ||
                        (_statusFilter == 'cancelled' &&
                            p.status.toLowerCase() == 'cancelled');
                    return matchesSearch && matchesStatus;
                  }).toList(growable: false);
                  filtered.sort((a, b) {
                    switch (_sortMode) {
                      case 'oldest':
                        return a.date.compareTo(b.date);
                      case 'highest':
                        return b.subtotal.compareTo(a.subtotal);
                      case 'lowest':
                        return a.subtotal.compareTo(b.subtotal);
                      case 'supplier':
                        return a.supplierName
                            .toLowerCase()
                            .compareTo(b.supplierName.toLowerCase());
                      case 'newest':
                      default:
                        return b.date.compareTo(a.date);
                    }
                  });
                  return filtered;
                },
              );
        _syncPurchaseReveal(purchases.length);
        final averagePurchase =
            monthlyCount == 0 ? 0.0 : monthlyTotal / monthlyCount;
        final visiblePurchaseCount =
            math.min(_visiblePurchaseCount, purchases.length);
        final pageInsets = VentioResponsive.pageInsets(context);
        return Focus(
          focusNode: _pageShortcutFocusNode,
          autofocus: true,
          onKeyEvent: _handlePurchasesShortcutKey,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: pageInsets,
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      LayoutBuilder(builder: (context, constraints) {
                        final compact = constraints.maxWidth < 650;
                        final indicator = PageDataLoadIndicator(
                          loadedCount: visiblePurchaseCount,
                          totalCount: purchases.length,
                        );
                        final title = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr.text('purchases'),
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text(tr.text('purchases_desc')),
                          ],
                        );
                        final button = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: widget.store.canManagePurchases
                                  ? () => _openPurchaseDialog(context)
                                  : null,
                              icon: const Icon(Icons.add_shopping_cart),
                              label: Text(tr.text('new_purchase')),
                            ),
                            OutlinedButton.icon(
                              onPressed: widget.store.canManagePurchases
                                  ? () => _openPurchaseReturnDialog(context)
                                  : null,
                              icon:
                                  const Icon(Icons.assignment_return_outlined),
                              label: Text(tr.text('new_purchase_return')),
                            ),
                          ],
                        );
                        return compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    Row(
                                      children: [
                                        Expanded(child: title),
                                        const SizedBox(width: 12),
                                        indicator,
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    button
                                  ])
                            : Row(children: [
                                Expanded(child: title),
                                const SizedBox(width: 12),
                                indicator,
                                const SizedBox(width: 12),
                                button
                              ]);
                      }),
                      const SizedBox(height: 8),
                      _buildPurchasesShortcutGuide(context, tr),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(
                              label: tr.text('purchase_total'),
                              value: formatUsdReferenceAmount(
                                  overview.totalPurchasesAmount,
                                  widget.store.storeProfile),
                              icon: Icons.shopping_cart_checkout),
                          _MetricCard(
                              label: tr.text('purchases_this_month'),
                              value: formatUsdReferenceAmount(
                                  monthlyTotal, widget.store.storeProfile),
                              icon: Icons.calendar_month_outlined),
                          _MetricCard(
                              label: tr.text('draft_purchases'),
                              value: formatUsdReferenceAmount(
                                  draftTotal, widget.store.storeProfile),
                              icon: Icons.pending_actions),
                          _MetricCard(
                              label: tr.text('avg_purchase'),
                              value: formatUsdReferenceAmount(
                                  averagePurchase, widget.store.storeProfile),
                              icon: Icons.insights_outlined),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: (_) => setState(_resetPurchaseReveal),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: tr.text('search_purchase_supplier_product'),
                          border: const OutlineInputBorder(),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: tr.text('clear_search'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(_resetPurchaseReveal);
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 620;
                          final filters = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                  label: Text(
                                      '${tr.text('all')} (${allPurchases.length})'),
                                  selected: _statusFilter == 'all',
                                  onSelected: (_) => setState(() {
                                        _statusFilter = 'all';
                                        _resetPurchaseReveal();
                                      })),
                              ChoiceChip(
                                  label: Text(
                                      '${tr.text('draft')} (${overview.draftCount})'),
                                  selected: _statusFilter == 'draft',
                                  onSelected: (_) => setState(() {
                                        _statusFilter = 'draft';
                                        _resetPurchaseReveal();
                                      })),
                              ChoiceChip(
                                  label: Text(
                                      '${tr.text('received')} (${overview.receivedCount})'),
                                  selected: _statusFilter == 'received',
                                  onSelected: (_) => setState(() {
                                        _statusFilter = 'received';
                                        _resetPurchaseReveal();
                                      })),
                              ChoiceChip(
                                  label: Text(
                                      '${tr.text('returned')} (${overview.returnedCount})'),
                                  selected: _statusFilter == 'returned',
                                  onSelected: (_) => setState(() {
                                        _statusFilter = 'returned';
                                        _resetPurchaseReveal();
                                      })),
                              ChoiceChip(
                                  label: Text(
                                      '${tr.text('cancelled')} (${overview.cancelledCount})'),
                                  selected: _statusFilter == 'cancelled',
                                  onSelected: (_) => setState(() {
                                        _statusFilter = 'cancelled';
                                        _resetPurchaseReveal();
                                      })),
                            ],
                          );
                          final sorter = DropdownButtonFormField<String>(
                            initialValue: _sortMode,
                            decoration: InputDecoration(
                                labelText: tr.text('sort_by'),
                                border: const OutlineInputBorder()),
                            items: [
                              DropdownMenuItem(
                                  value: 'newest',
                                  child: Text(tr.text('newest_first'))),
                              DropdownMenuItem(
                                  value: 'oldest',
                                  child: Text(tr.text('oldest_first'))),
                              DropdownMenuItem(
                                  value: 'highest',
                                  child: Text(tr.text('highest_amount'))),
                              DropdownMenuItem(
                                  value: 'lowest',
                                  child: Text(tr.text('lowest_amount'))),
                              DropdownMenuItem(
                                  value: 'supplier',
                                  child: Text(tr.text('supplier_name_sort'))),
                            ],
                            onChanged: (value) => setState(() {
                              _sortMode = value ?? 'newest';
                              _resetPurchaseReveal();
                            }),
                          );
                          if (compact) {
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  filters,
                                  const SizedBox(height: 12),
                                  sorter
                                ]);
                          }
                          return Row(children: [
                            Expanded(child: filters),
                            SizedBox(width: 220, child: sorter)
                          ]);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              if (purchases.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      pageInsets.left, 0, pageInsets.right, pageInsets.bottom),
                  sliver: SliverToBoxAdapter(
                    child: Text(tr.text('no_purchases_yet')),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      pageInsets.left, 0, pageInsets.right, pageInsets.bottom),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final purchase = purchases[index];
                        return _PurchaseTile(
                          purchase: purchase,
                          storeProfile: widget.store.storeProfile,
                          onTap: () => _showPurchaseDetails(context, purchase),
                          onReceive: purchase.status == 'Draft'
                              ? (widget.store.canManagePurchases
                                  ? () => _receivePurchase(context, purchase.id)
                                  : null)
                              : null,
                          onCancel: purchase.isReceived &&
                                  !purchase.isReturned &&
                                  !purchase.isPurchaseReturn
                              ? (widget.store.hasPermission(
                                      AppPermission.purchasesCancel)
                                  ? () => _returnPurchase(context, purchase.id)
                                  : null)
                              : null,
                          onDeleteDraft: !purchase.isReceived &&
                                  !purchase.isCancelled &&
                                  widget.store.canManagePurchases
                              ? () => _deleteDraftPurchase(context, purchase.id)
                              : null,
                          onPermanentDelete: null,
                          onDuplicate: widget.store.canManagePurchases &&
                                  !purchase.isPurchaseReturn
                              ? () => _openPurchaseDialog(context,
                                  template: purchase)
                              : null,
                          onEdit: ((purchase.isDraft || purchase.isReceived) &&
                                      !purchase.isCancelled &&
                                      !purchase.isReturned &&
                                      !purchase.isPurchaseReturn &&
                                      widget.store.canManagePurchases) ||
                                  (purchase.isReturned &&
                                      widget.store.canManagePurchases &&
                                      widget.store.hasPermission(
                                          AppPermission.purchasesCancel))
                              ? () => _openPurchaseDialog(context,
                                  editPurchase: purchase)
                              : null,
                          formatDate: _formatShortDate,
                        );
                      },
                      childCount: visiblePurchaseCount,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PurchaseDialogSession {
  _PurchaseDialogSession({
    required this.widget,
    required this.pageState,
    required this.context,
    required this.isMounted,
    required this.stateSet,
    required this.tr,
    required this.formKey,
    required this.source,
    required this.items,
    required this.sqliteProducts,
    required this.sqliteSuppliers,
    required this.purchaseProducts,
    required this.purchaseSuppliers,
    required this.supplierId,
    required this.supplierName,
    required this.initialWarehouse,
    required this.selectedWarehouseId,
    required this.selectedWarehouseName,
    required this.selectedProduct,
    required this.selectedUnit,
    required this.selectedExpiryDate,
    required this.qtyController,
    required this.costController,
    required this.productSearchController,
    required this.paidAmountController,
    required this.dialogShortcutFocusNode,
    required this.productSearchFocusNode,
    required this.qtyFocusNode,
    required this.costFocusNode,
    required this.addLineFocusNode,
    required this.paidAmountFocusNode,
    required this.productSearchFocusRequested,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.editingReceivedPurchase,
    required this.editingReturnedPurchase,
    required this.editingPostedPurchase,
    required this.sourceCurrency,
    required this.costCurrency,
    required this.receiveNow,
    required this.isClosingPurchaseDialog,
    required this.activePurchaseDialogContext,
    required this.activePurchaseDialogSetState,
    required this.template,
    required this.editPurchase,
  });
  final PurchasesPage widget;
  final _PurchasesPageState pageState;
  final BuildContext context;
  final bool Function() isMounted;
  final void Function(VoidCallback) stateSet;
  dynamic tr;
  dynamic formKey;
  dynamic source;
  dynamic items;
  dynamic sqliteProducts;
  dynamic sqliteSuppliers;
  dynamic purchaseProducts;
  dynamic purchaseSuppliers;
  dynamic supplierId;
  dynamic supplierName;
  dynamic initialWarehouse;
  dynamic selectedWarehouseId;
  dynamic selectedWarehouseName;
  dynamic selectedProduct;
  dynamic selectedUnit;
  dynamic selectedExpiryDate;
  dynamic qtyController;
  dynamic costController;
  dynamic productSearchController;
  dynamic paidAmountController;
  dynamic dialogShortcutFocusNode;
  dynamic productSearchFocusNode;
  dynamic qtyFocusNode;
  dynamic costFocusNode;
  dynamic addLineFocusNode;
  dynamic paidAmountFocusNode;
  dynamic productSearchFocusRequested;
  dynamic paymentStatus;
  dynamic paymentMethod;
  dynamic editingReceivedPurchase;
  dynamic editingReturnedPurchase;
  dynamic editingPostedPurchase;
  dynamic sourceCurrency;
  dynamic costCurrency;
  dynamic receiveNow;
  dynamic isClosingPurchaseDialog;
  dynamic activePurchaseDialogContext;
  dynamic activePurchaseDialogSetState;
  dynamic template;
  dynamic editPurchase;

  bool get mounted => isMounted();

  void setState(VoidCallback callback) => stateSet(callback);

  String _formatQuantity(double value) =>
      _PurchasesPageStateMethods1(pageState)._formatQuantity(value);

  Future<String?> _scanBarcodeWithCamera() =>
      _PurchasesPageStateMethods1(pageState)._scanBarcodeWithCamera();

  Future<List<Product>> _resolvePurchaseSearchProducts(
    List<Product> fallbackProducts,
    String query,
  ) =>
      _PurchasesPageStateMethods1(pageState)
          ._resolvePurchaseSearchProducts(fallbackProducts, query);

  Future<List<BatchAllocation>?> _promptBatchAllocations(
    BuildContext context, {
    required Product product,
    required double quantity,
  }) =>
      _PurchasesPageStateMethods1(pageState)._promptBatchAllocations(
        context,
        product: product,
        quantity: quantity,
      );

  Widget _buildPurchaseDialogShortcutGuide(
    BuildContext context,
    AppLocalizations tr,
  ) =>
      _PurchasesPageStateMethods1(pageState)
          ._buildPurchaseDialogShortcutGuide(context, tr);
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

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: VentioResponsive.clampToScreen(
          context,
          VentioResponsive.adaptiveWidth(context,
              mobile: 190, tablet: 220, desktop: 260),
          min: 160,
        ),
        child: Card(
          child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child: Row(children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label),
                    Text(value, style: Theme.of(context).textTheme.titleLarge)
                  ]))
            ]),
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _PurchaseQueryResult {
  const _PurchaseQueryResult({
    required this.items,
    required this.totalCount,
    required this.overview,
  });

  final List<Purchase> items;
  final int totalCount;
  final PurchasesOverview overview;

  bool get hasMore => items.length < totalCount;
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.purchase,
    required this.storeProfile,
    required this.formatDate,
    this.onTap,
    this.onReceive,
    this.onCancel,
    this.onDeleteDraft,
    this.onPermanentDelete,
    this.onDuplicate,
    this.onEdit,
  });

  final Purchase purchase;
  final StoreProfile storeProfile;
  final String Function(DateTime date) formatDate;
  final VoidCallback? onTap,
      onReceive,
      onCancel,
      onDeleteDraft,
      onPermanentDelete,
      onDuplicate,
      onEdit;

  String _formatQuantity(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final statusText = purchase.isPurchaseReturn
        ? tr.text('purchase_return')
        : purchase.isReturned
            ? tr.text('returned')
            : purchase.status.toLowerCase() == 'cancelled'
                ? tr.text('cancelled')
                : purchase.isReceived
                    ? tr.text('received')
                    : tr.text('draft');
    final statusColor = purchase.isPurchaseReturn
        ? Colors.blueGrey
        : purchase.isReturned
            ? Colors.blueGrey
            : purchase.status.toLowerCase() == 'cancelled'
                ? Colors.red
                : purchase.isReceived
                    ? Colors.green
                    : Colors.orange;
    final statusIcon = purchase.isPurchaseReturn
        ? Icons.assignment_return_outlined
        : purchase.isReturned
            ? Icons.assignment_return_outlined
            : purchase.status.toLowerCase() == 'cancelled'
                ? Icons.cancel_outlined
                : purchase.isReceived
                    ? Icons.inventory_2_outlined
                    : Icons.pending_actions;
    final amount = formatUsdReferenceAmount(purchase.subtotal, storeProfile);
    final supplier = purchase.supplierName.trim().isEmpty
        ? '-'
        : purchase.supplierName.trim();
    final summary =
        '${purchase.items.length} ${tr.text('items')} • ${_formatQuantity(purchase.totalUnits)} ${tr.text('units')} • ${formatDate(purchase.date)}';

    final actionsMenu = PopupMenuButton<String>(
      tooltip: tr.text('actions'),
      onSelected: (value) {
        if (value == 'duplicate') onDuplicate?.call();
        if (value == 'edit') onEdit?.call();
        if (value == 'receive') onReceive?.call();
        if (value == 'return') onCancel?.call();
        if (value == 'delete_draft') onDeleteDraft?.call();
        if (value == 'permanent_delete') onPermanentDelete?.call();
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(tr.text('edit_purchase')))),
        PopupMenuItem(
            value: 'duplicate',
            child: ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: Text(tr.text('duplicate_purchase')))),
        if (onReceive != null)
          PopupMenuItem(
              value: 'receive',
              child: ListTile(
                  leading: const Icon(Icons.download_done),
                  title: Text(tr.text('receive')))),
        if (onCancel != null)
          PopupMenuItem(
              value: 'return',
              child: ListTile(
                  leading: const Icon(Icons.assignment_return_outlined),
                  title: Text(tr.text('return_purchase')))),
        if (onDeleteDraft != null)
          PopupMenuItem(
              value: 'delete_draft',
              child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(tr.text('delete_draft_purchase')))),
        if (onPermanentDelete != null)
          PopupMenuItem(
              value: 'permanent_delete',
              child: ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: Text(tr.text('permanently_delete')))),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(statusIcon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(purchase.purchaseNo,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(supplier,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(statusText,
                              style: TextStyle(color: statusColor)),
                        ),
                        Text(summary,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    if (isCompact) ...[
                      const SizedBox(height: 8),
                      Text(amount,
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isCompact)
                Text(amount, style: Theme.of(context).textTheme.titleMedium),
              actionsMenu,
            ],
          ),
        ),
      ),
    );
  }
}
