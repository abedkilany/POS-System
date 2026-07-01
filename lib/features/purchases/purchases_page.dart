// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/revision_cache.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../data/app_store.dart';
import '../../widgets/page_data_load_indicator.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/user_role.dart';
import '../barcode/barcode_scanner_page.dart';

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

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

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
      _dataFuture = widget.store.ensurePurchasesPageDataLoaded();
    }
  }

  String _formatQuantity(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    _dataFuture = widget.store.ensurePurchasesPageDataLoaded();
    HardwareKeyboard.instance.addHandler(_handlePurchasesHardwareShortcutKey);
  }

  void _resetPurchaseReveal() {
    _purchaseRevealTimer?.cancel();
    _purchaseRevealTimer = null;
    _visiblePurchaseCount = 100;
    _purchaseRevealTargetCount = 0;
  }

  void _syncPurchaseReveal(int totalCount) {
    _purchaseRevealTargetCount = totalCount;
    if (_visiblePurchaseCount > totalCount) {
      _visiblePurchaseCount = totalCount;
    }
    if (_visiblePurchaseCount >= totalCount) {
      _purchaseRevealTimer?.cancel();
      _purchaseRevealTimer = null;
      return;
    }
    _purchaseRevealTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        _purchaseRevealTimer = null;
        return;
      }
      if (_visiblePurchaseCount >= _purchaseRevealTargetCount) {
        timer.cancel();
        _purchaseRevealTimer = null;
        return;
      }
      setState(() {
        _visiblePurchaseCount = math.min(
          _purchaseRevealTargetCount,
          _visiblePurchaseCount + 100,
        );
      });
      if (_visiblePurchaseCount >= _purchaseRevealTargetCount) {
        timer.cancel();
        _purchaseRevealTimer = null;
      }
    });
  }

  String _formatShortDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  bool _purchaseProductMatchesSearch(Product product, String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    return product.name.toLowerCase().contains(q) ||
        product.code.toLowerCase().contains(q) ||
        product.barcode.toLowerCase().contains(q) ||
        product.effectivePurchaseUnits.any((unit) =>
            unit.name.toLowerCase().contains(q) ||
            unit.barcode.toLowerCase().contains(q)) ||
        product.effectiveSaleUnits.any((unit) =>
            unit.name.toLowerCase().contains(q) ||
            unit.barcode.toLowerCase().contains(q));
  }

  Future<List<Product>> _resolvePurchaseSearchProducts(
    List<Product> fallbackProducts,
    String query,
  ) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return fallbackProducts;
    }
    final sqlite = await LocalDatabaseService.queryProductsFromSqlite(
      query: normalized,
      limit: 80,
      activeOnly: true,
      stockTrackedOnly: true,
    );
    if (sqlite != null) {
      return sqlite.items;
    }
    return fallbackProducts
        .where((product) => _purchaseProductMatchesSearch(product, normalized))
        .take(80)
        .toList(growable: false);
  }

  Future<String?> _scanBarcodeWithCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PageTimingScope(
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(),
        ),
      ),
    );
    final trimmed = code?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

  bool _handlePurchasesHardwareShortcutKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    return _handlePurchasesShortcutKey(_pageShortcutFocusNode, event) ==
        KeyEventResult.handled;
  }

  KeyEventResult _handlePurchasesShortcutKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return KeyEventResult.ignored;
    final action = SaleShortcutSettings.load().purchasesActionForKey(keyName);
    if (action == null) return KeyEventResult.ignored;
    _executePurchasesShortcut(action);
    return KeyEventResult.handled;
  }

  Future<void> _executePurchasesShortcut(PurchasesShortcutAction action) async {
    switch (action) {
      case PurchasesShortcutAction.newPurchase:
        await _openPurchaseDialog(context);
        break;
      case PurchasesShortcutAction.focusSearch:
        _searchFocusNode.requestFocus();
        break;
      case PurchasesShortcutAction.filterAll:
        setState(() {
          _statusFilter = 'all';
          _resetPurchaseReveal();
        });
        break;
      case PurchasesShortcutAction.filterDraft:
        setState(() {
          _statusFilter = 'draft';
          _resetPurchaseReveal();
        });
        break;
      case PurchasesShortcutAction.filterReceived:
        setState(() {
          _statusFilter = 'received';
          _resetPurchaseReveal();
        });
        break;
      case PurchasesShortcutAction.clearSearch:
        if (_searchController.text.isNotEmpty) {
          _searchController.clear();
          setState(() => _resetPurchaseReveal());
        } else {
          _searchFocusNode.unfocus();
        }
        break;
    }
  }

  Widget _buildPurchasesShortcutGuide(
      BuildContext context, AppLocalizations tr) {
    final settings = SaleShortcutSettings.load();
    final chips = <Widget>[];
    for (final action in PurchasesShortcutAction.values) {
      final keyName = settings.keyForPurchasesAction(action);
      if (keyName == null || keyName == SaleShortcutSettings.noneKey) continue;
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.keyboard_outlined, size: 16),
        label: Text('$keyName ${tr.text(action.labelKey)}'),
      ));
    }
    if (chips.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(tr.text('shortcuts_disabled_for_page'),
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        Text('${tr.text('shortcut_guide')}: ',
            style: Theme.of(context).textTheme.bodySmall),
        ...chips.expand((chip) => [chip, const SizedBox(width: 6)]),
      ]),
    );
  }

  Widget _buildPurchaseDialogShortcutGuide(
      BuildContext context, AppLocalizations tr) {
    final settings = SaleShortcutSettings.load();
    final chips = <Widget>[];
    for (final action in PurchaseDialogShortcutAction.values) {
      final keyName = settings.keyForPurchaseDialogAction(action);
      if (keyName == null || keyName == SaleShortcutSettings.noneKey) continue;
      chips.add(Padding(
        padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
        child: Chip(
          visualDensity: VisualDensity.compact,
          label: Text('$keyName ${tr.text(action.labelKey)}'),
        ),
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(children: chips);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewPurchases) {
      return const _AccessDeniedScaffold(
        title: 'Purchases',
        message: 'You do not have access to purchase records.',
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
                        final button = FilledButton.icon(
                          onPressed: widget.store.canManagePurchases
                              ? () => _openPurchaseDialog(context)
                              : null,
                          icon: const Icon(Icons.add_shopping_cart),
                          label: Text(tr.text('new_purchase')),
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
                          onCancel: purchase.isReceived && !purchase.isReturned
                              ? (widget.store.hasPermission(
                                          AppPermission.purchasesCancel) ||
                                      widget.store.canManagePurchases
                                  ? () => _returnPurchase(context, purchase.id)
                                  : null)
                              : null,
                          onDeleteDraft: !purchase.isReceived &&
                                  !purchase.isCancelled &&
                                  widget.store.canManagePurchases
                              ? () => _deleteDraftPurchase(context, purchase.id)
                              : null,
                          onPermanentDelete:
                              purchase.status.toLowerCase() == 'cancelled' &&
                                      widget.store.hasPermission(
                                          AppPermission.databaseManage)
                                  ? () => _permanentlyDeletePurchase(
                                      context, purchase.id)
                                  : null,
                          onDuplicate: widget.store.canManagePurchases
                              ? () => _openPurchaseDialog(context,
                                  template: purchase)
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

  Future<Map<String, Object?>?> _queryPurchasesOverviewMapFromSqlite() async {
    final key = '${widget.store.purchasesRevision}';
    if (_purchaseOverviewFuture == null || _purchaseOverviewFutureKey != key) {
      _purchaseOverviewFutureKey = key;
      _purchaseOverviewFuture =
          LocalDatabaseService.buildPurchasesOverviewFromSqlite(
        reference: DateTime.now(),
      );
    }
    return _purchaseOverviewFuture!;
  }

  PurchasesOverview _overviewFromMap(Map<String, Object?>? data) {
    int readInt(String key) => (data?[key] as num?)?.toInt() ?? 0;
    double readDouble(String key) => (data?[key] as num?)?.toDouble() ?? 0.0;
    if (data == null) {
      return const PurchasesOverview(
        totalCount: 0,
        totalPurchasesAmount: 0,
        monthlyTotal: 0,
        monthlyCount: 0,
        draftTotal: 0,
        draftCount: 0,
        receivedCount: 0,
        returnedCount: 0,
        cancelledCount: 0,
        pendingPurchaseCount: 0,
      );
    }
    return PurchasesOverview(
      totalCount: readInt('totalCount'),
      totalPurchasesAmount: readDouble('totalPurchasesAmount'),
      monthlyTotal: readDouble('monthlyTotal'),
      monthlyCount: readInt('monthlyCount'),
      draftTotal: readDouble('draftTotal'),
      draftCount: readInt('draftCount'),
      receivedCount: readInt('receivedCount'),
      returnedCount: readInt('returnedCount'),
      cancelledCount: readInt('cancelledCount'),
      pendingPurchaseCount: readInt('pendingPurchaseCount'),
    );
  }

  Future<_PurchaseQueryResult?> _queryPurchasesFromSqlite(
    String normalizedQuery,
  ) async {
    final limit = math.max(1, _visiblePurchaseCount);
    final key =
        '${widget.store.purchasesRevision}|$_statusFilter|$_sortMode|$normalizedQuery|$limit';
    if (_purchaseQueryFuture == null || _purchaseQueryFutureKey != key) {
      _purchaseQueryFutureKey = key;
      _purchaseQueryFuture = () async {
        final page = await LocalDatabaseService.queryPurchasesFromSqlite(
          query: normalizedQuery,
          status: _statusFilter,
          limit: limit,
          sortMode: _sortMode,
        );
        if (page == null) return null;
        final overview =
            _overviewFromMap(await _queryPurchasesOverviewMapFromSqlite());
        return _PurchaseQueryResult(
          items: page.items,
          totalCount: page.totalCount,
          overview: overview,
        );
      }();
    }
    return _purchaseQueryFuture!;
  }

  void _loadMorePurchases(int totalCount) {
    setState(() {
      _purchaseRevealTimer?.cancel();
      _purchaseRevealTimer = null;
      _visiblePurchaseCount = math.min(totalCount, _visiblePurchaseCount + 100);
    });
  }

  Widget _buildPurchasesSqliteView(
    BuildContext context,
    AppLocalizations tr,
    _PurchaseQueryResult result,
    String normalizedQuery,
  ) {
    final overview = result.overview;
    final purchases = result.items;
    final totalCount = result.totalCount;
    final averagePurchase = overview.monthlyCount == 0
        ? 0.0
        : overview.monthlyTotal / overview.monthlyCount;
    _syncPurchaseReveal(totalCount);

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;
            final indicator = PageDataLoadIndicator(
              loadedCount: purchases.length,
              totalCount: totalCount,
            );
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('purchases'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(tr.text('purchases_desc')),
              ],
            );
            final button = FilledButton.icon(
              onPressed: widget.store.canManagePurchases
                  ? () => _openPurchaseDialog(context)
                  : null,
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(tr.text('new_purchase')),
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
                      overview.totalPurchasesAmount, widget.store.storeProfile),
                  icon: Icons.shopping_cart_checkout),
              _MetricCard(
                  label: tr.text('purchases_this_month'),
                  value: formatUsdReferenceAmount(
                      overview.monthlyTotal, widget.store.storeProfile),
                  icon: Icons.calendar_month_outlined),
              _MetricCard(
                  label: tr.text('draft_purchases'),
                  value: formatUsdReferenceAmount(
                      overview.draftTotal, widget.store.storeProfile),
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
              suffixIcon: normalizedQuery.isEmpty
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
                      label: Text('${tr.text('all')} (${overview.totalCount})'),
                      selected: _statusFilter == 'all',
                      onSelected: (_) => setState(() {
                            _statusFilter = 'all';
                            _resetPurchaseReveal();
                          })),
                  ChoiceChip(
                      label:
                          Text('${tr.text('draft')} (${overview.draftCount})'),
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
                      value: 'newest', child: Text(tr.text('newest_first'))),
                  DropdownMenuItem(
                      value: 'oldest', child: Text(tr.text('oldest_first'))),
                  DropdownMenuItem(
                      value: 'highest', child: Text(tr.text('highest_amount'))),
                  DropdownMenuItem(
                      value: 'lowest', child: Text(tr.text('lowest_amount'))),
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
                    children: [filters, const SizedBox(height: 12), sorter]);
              }
              return Row(children: [
                Expanded(child: filters),
                SizedBox(width: 220, child: sorter)
              ]);
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: purchases.isEmpty
                ? Center(child: Text(tr.text('no_purchases_yet')))
                : ListView.separated(
                    itemCount: purchases.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (context, index) {
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
                        onCancel: purchase.isReceived && !purchase.isReturned
                            ? (widget.store.hasPermission(
                                        AppPermission.purchasesCancel) ||
                                    widget.store.canManagePurchases
                                ? () => _returnPurchase(context, purchase.id)
                                : null)
                            : null,
                        onDeleteDraft: !purchase.isReceived &&
                                !purchase.isCancelled &&
                                widget.store.canManagePurchases
                            ? () => _deleteDraftPurchase(context, purchase.id)
                            : null,
                        onPermanentDelete: purchase.status.toLowerCase() ==
                                    'cancelled' &&
                                widget.store
                                    .hasPermission(AppPermission.databaseManage)
                            ? () =>
                                _permanentlyDeletePurchase(context, purchase.id)
                            : null,
                        onDuplicate: widget.store.canManagePurchases
                            ? () =>
                                _openPurchaseDialog(context, template: purchase)
                            : null,
                        formatDate: _formatShortDate,
                      );
                    },
                  ),
          ),
          if (result.hasMore) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                onPressed: () => _loadMorePurchases(totalCount),
                icon: const Icon(Icons.expand_more),
                label: Text(tr.isArabic ? 'عرض المزيد' : 'Load more'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _receivePurchase(BuildContext context, String id) async {
    if (!widget.store.canManagePurchases) return;
    try {
      await widget.store.receivePurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('purchase_received'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteDraftPurchase(BuildContext context, String id) async {
    if (!widget.store.canManagePurchases) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('delete_draft_purchase')),
        content: Text(
            AppLocalizations.of(context).text('delete_draft_purchase_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).text('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.deleteDraftPurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('purchase_deleted'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _permanentlyDeletePurchase(
      BuildContext context, String id) async {
    if (!widget.store.hasPermission(AppPermission.databaseManage)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            AppLocalizations.of(context).text('permanently_delete_purchase')),
        content: Text(AppLocalizations.of(context)
            .text('permanently_delete_purchase_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                  AppLocalizations.of(context).text('permanently_delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.permanentlyDeleteCancelledPurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('purchase_permanently_deleted'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _returnPurchase(BuildContext context, String id) async {
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.purchasesCancel,
      AppPermission.purchasesManage,
    })) return;
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('return_purchase')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppLocalizations.of(context).text('return_purchase_desc')),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)
                      .text('return_reason_optional')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).text('confirm'))),
        ],
      ),
    );
    if (ok != true) {
      reasonController.dispose();
      return;
    }
    final reason = reasonController.text.trim();
    reasonController.dispose();
    try {
      await widget.store.returnPurchase(id, reason: reason);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('purchase_returned_stock_reversed'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showPurchaseDetails(
      BuildContext context, Purchase purchase) async {
    final tr = AppLocalizations.of(context);
    final statusText = purchase.isReturned
        ? tr.text('returned')
        : purchase.status.toLowerCase() == 'cancelled'
            ? tr.text('cancelled')
            : purchase.isReceived
                ? tr.text('received')
                : tr.text('draft');
    final statusColor = purchase.isReturned
        ? Colors.blueGrey
        : purchase.status.toLowerCase() == 'cancelled'
            ? Colors.red
            : purchase.isReceived
                ? Colors.green
                : Colors.orange;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) => Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(purchase.purchaseNo,
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                        label: Text(purchase.supplierName.isEmpty
                            ? '-'
                            : purchase.supplierName),
                        avatar: const Icon(Icons.local_shipping_outlined,
                            size: 18)),
                    Chip(
                        label: Text(statusText),
                        avatar:
                            Icon(Icons.circle, size: 14, color: statusColor)),
                    Chip(
                        label: Text(
                            '${purchase.items.length} ${tr.text('items')}')),
                    Chip(
                        label: Text(
                            '${_formatQuantity(purchase.totalUnits)} ${tr.text('units')}')),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: VentioResponsive.cardInsets(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                            label: tr.text('date'),
                            value: _formatShortDate(purchase.date)),
                        if (purchase.cancelledAt != null)
                          _DetailRow(
                              label: tr.text('cancelled_at'),
                              value: _formatShortDate(purchase.cancelledAt!)),
                        if (purchase.cancelReason.trim().isNotEmpty)
                          _DetailRow(
                              label: tr.text('cancel_reason'),
                              value: purchase.cancelReason.trim()),
                        if (purchase.isCancelled)
                          _DetailRow(
                              label: tr.text('reversal_status'),
                              value: purchase.reversalApplied
                                  ? tr.text('reversal_applied')
                                  : tr.text('reversal_not_applied')),
                        _DetailRow(
                            label: tr.text('final_total'),
                            value: formatUsdReferenceAmount(
                                purchase.subtotal, widget.store.storeProfile)),
                        if (purchase.note.trim().isNotEmpty)
                          _DetailRow(
                              label: tr.text('notes'),
                              value: purchase.note.trim()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr.text('items'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...purchase.items.map((item) => Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                            '${_formatQuantity(item.quantity)} ${item.purchaseUnitName.isEmpty ? tr.text('unit') : item.purchaseUnitName} â€¢ ${formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency)}'),
                        trailing: Text(formatUsdReferenceAmount(
                            item.lineTotal, widget.store.storeProfile)),
                      ),
                    )),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openPurchaseDialog(context, template: purchase);
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(tr.text('duplicate_purchase')),
                    ),
                    if (!purchase.isReceived && !purchase.isCancelled)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _receivePurchase(context, purchase.id);
                        },
                        icon: const Icon(Icons.download_done),
                        label: Text(tr.text('receive')),
                      ),
                    if (purchase.isReceived && !purchase.isReturned)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _returnPurchase(context, purchase.id);
                        },
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: Text(tr.text('return_purchase')),
                      ),
                    if (!purchase.isReceived && !purchase.isCancelled)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteDraftPurchase(context, purchase.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(tr.text('delete_draft_purchase')),
                      ),
                    if (purchase.isCancelled &&
                        widget.store
                            .hasPermission(AppPermission.databaseManage))
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _permanentlyDeletePurchase(context, purchase.id);
                        },
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: Text(tr.text('permanently_delete')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPurchaseDialog(BuildContext context,
      {Purchase? template}) async {
    if (!widget.store.canManagePurchases) return;
    final tr = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final items = template == null
        ? <PurchaseItem>[]
        : List<PurchaseItem>.of(template.items);
    var purchaseProducts = widget.store.products
        .where((product) => product.trackStock && product.isActive)
        .toList();
    String supplierId = template?.supplierId ??
        (widget.store.suppliers.isNotEmpty
            ? widget.store.suppliers.first.id
            : '');
    String supplierName = template?.supplierName ??
        (widget.store.suppliers.isNotEmpty
            ? widget.store.suppliers.first.name
            : '');
    if (supplierId.isNotEmpty &&
        !widget.store.suppliers.any((supplier) => supplier.id == supplierId)) {
      supplierId = widget.store.suppliers.isNotEmpty
          ? widget.store.suppliers.first.id
          : '';
      supplierName = widget.store.suppliers.isNotEmpty
          ? widget.store.suppliers.first.name
          : supplierName;
    }
    Product? selectedProduct =
        purchaseProducts.isNotEmpty ? purchaseProducts.first : null;
    ProductSaleUnit? selectedUnit =
        selectedProduct?.effectivePurchaseUnits.first;
    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController();
    final productSearchController = TextEditingController();
    final paidAmountController = TextEditingController();
    final dialogShortcutFocusNode = FocusNode();
    final qtyFocusNode = FocusNode();
    final costFocusNode = FocusNode();
    final paidAmountFocusNode = FocusNode();
    String paymentStatus = 'paid';
    String paymentMethod = 'Cash';
    String costCurrency = selectedProduct?.costCurrency ??
        widget.store.storeProfile.defaultProductCurrency;
    bool receiveNow = false;

    SupplierProductPrice? selectedSupplierPriceFor(Product product) {
      return supplierId.isEmpty
          ? null
          : widget.store.supplierProductPriceFor(
              productId: product.id, supplierId: supplierId);
    }

    PurchaseItem? suggestedPurchaseItem(Product product) {
      return supplierId.isEmpty
          ? null
          : widget.store.lastPurchaseItemFor(
              productId: product.id, supplierId: supplierId);
    }

    double suggestedBaseCost(Product product) {
      final supplierPrice = selectedSupplierPriceFor(product);
      if (supplierPrice != null) {
        return toUsdReferencePrice(supplierPrice.cost, supplierPrice.currency,
            widget.store.storeProfile);
      }
      return suggestedPurchaseItem(product)?.unitCostPerBase ??
          widget.store.lastPurchasePriceForProduct(product.id) ??
          product.usdCost;
    }

    String suggestedCostCurrency(Product product) {
      final supplierPrice = selectedSupplierPriceFor(product);
      return supplierPrice?.currency ??
          suggestedPurchaseItem(product)?.unitCostCurrency ??
          widget.store
              .lastPurchaseItemForProduct(product.id)
              ?.unitCostCurrency ??
          product.costCurrency;
    }

    void applySuggestedSupplierPrice() {
      final product = selectedProduct;
      final unit = selectedUnit;
      if (product == null || unit == null) {
        costController.text = '0';
        return;
      }
      costCurrency = suggestedCostCurrency(product);
      final suggested = suggestedBaseCost(product) * unit.conversionToBase;
      final displayCost = fromUsdReferencePrice(
          suggested, costCurrency, widget.store.storeProfile);
      costController.text =
          displayCost.toStringAsFixed(costCurrency == 'LBP' ? 0 : 2);
    }

    selectedUnit = selectedProduct?.effectivePurchaseUnits.first;
    applySuggestedSupplierPrice();

    String priceHintForSelectedProduct() {
      final product = selectedProduct;
      if (product == null) return '';
      final configuredSupplierPrice = supplierId.isEmpty
          ? null
          : widget.store.supplierProductPriceFor(
              productId: product.id, supplierId: supplierId);
      final supplierPrice = supplierId.isEmpty
          ? null
          : widget.store.lastPurchasePriceFor(
              productId: product.id, supplierId: supplierId);
      final lastGeneral = widget.store.lastPurchasePriceForProduct(product.id);
      final avg = widget.store.averagePurchaseCostForProduct(product.id);
      final supplierCount = widget.store.supplierCountForProduct(product.id);
      final parts = <String>[];
      if (configuredSupplierPrice != null) {
        parts.add(
            '${tr.text('supplier_price')}: ${formatCurrency(configuredSupplierPrice.cost, currency: configuredSupplierPrice.currency)}');
      }
      if (supplierPrice != null) {
        parts.add(
            '${tr.text('supplier_last_base')}: ${formatUsdReferenceAmount(supplierPrice, widget.store.storeProfile)}');
      }
      if (lastGeneral != null) {
        parts.add(
            '${tr.text('last_base')}: ${formatUsdReferenceAmount(lastGeneral, widget.store.storeProfile)}');
      }
      if (avg > 0) {
        parts.add(
            '${tr.text('avg_base')}: ${formatUsdReferenceAmount(avg, widget.store.storeProfile)}');
      }
      if (supplierCount > 0) {
        parts.add(
            '$supplierCount ${tr.text(supplierCount == 1 ? 'supplier' : 'suppliers')}');
      }
      return parts.join(' â€¢ ');
    }

    String unitConversionSummary(PurchaseItem item) {
      final unitName = item.purchaseUnitName.isEmpty
          ? tr.text('unit')
          : item.purchaseUnitName;
      return '${_formatQuantity(item.quantity)} $unitName = ${_formatQuantity(item.baseQuantity)} ${tr.text('base')} ${tr.text(item.baseQuantity == 1 ? 'unit' : 'units')}';
    }

    String selectedUnitConversionSummary() {
      final unit = selectedUnit;
      final qty = double.tryParse(qtyController.text.trim()) ?? 0;
      if (unit == null || qty <= 0) return '';
      return '${_formatQuantity(qty)} ${unit.name} = ${_formatQuantity(qty * unit.conversionToBase)} ${tr.text('base')} ${tr.text(qty * unit.conversionToBase == 1 ? 'unit' : 'units')}';
    }

    void showPurchaseError(String message) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    Future<bool> confirmDiscardIfNeeded(BuildContext confirmContext) async {
      if (items.isEmpty) return true;
      return await showDialog<bool>(
            context: confirmContext,
            builder: (alertContext) => AlertDialog(
              title: Text(tr.text('discard_purchase_title')),
              content: Text(tr.text('discard_purchase_message')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(alertContext, false),
                    child: Text(tr.text('keep_editing'))),
                FilledButton(
                    onPressed: () => Navigator.pop(alertContext, true),
                    child: Text(tr.text('discard'))),
              ],
            ),
          ) ??
          false;
    }

    Future<void> createQuickSupplier(StateSetter setDialogState) async {
      final nameController = TextEditingController();
      final phoneController = TextEditingController();
      final created = await showModalBottomSheet<Supplier>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('add_supplier'),
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                  controller: nameController,
                  decoration:
                      InputDecoration(labelText: tr.text('supplier_name')),
                  autofocus: true),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneController,
                  decoration: InputDecoration(labelText: tr.text('phone'))),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(tr.text('save')),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(
                      sheetContext,
                      Supplier(
                        id: 'supplier_${DateTime.now().microsecondsSinceEpoch}',
                        name: name,
                        phone: phoneController.text.trim(),
                        address: '',
                        notes: '',
                      ));
                },
              ),
            ],
          ),
        ),
      );
      nameController.dispose();
      phoneController.dispose();
      if (created == null) return;
      try {
        await widget.store.addOrUpdateSupplier(created);
        supplierId = created.id;
        supplierName = created.name;
        setDialogState(() {});
      } catch (error) {
        if (mounted) showPurchaseError(error.toString());
      }
    }

    Future<void> createQuickProduct(StateSetter setDialogState) async {
      final nameController = TextEditingController();
      final barcodeQuickController = TextEditingController();
      final created = await showModalBottomSheet<Product>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('add_product'),
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                  controller: nameController,
                  decoration:
                      InputDecoration(labelText: tr.text('product_name')),
                  autofocus: true),
              const SizedBox(height: 12),
              TextField(
                controller: barcodeQuickController,
                decoration: InputDecoration(
                  labelText: tr.text('barcode'),
                  suffixIcon: IconButton(
                    tooltip: tr.text('scan_with_camera'),
                    onPressed: () async {
                      final code = await _scanBarcodeWithCamera();
                      if (code == null) return;
                      barcodeQuickController.text = code;
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(tr.text('save')),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final now = DateTime.now().microsecondsSinceEpoch;
                  Navigator.pop(
                      sheetContext,
                      Product(
                        id: 'product_$now',
                        name: name,
                        code: 'PRD-$now',
                        barcode: barcodeQuickController.text.trim(),
                        price: 0,
                        cost: 0,
                        stock: 0,
                        category: 'General',
                        unit: tr.text('unit'),
                        trackStock: true,
                        isActive: true,
                      ));
                },
              ),
            ],
          ),
        ),
      );
      nameController.dispose();
      barcodeQuickController.dispose();
      if (created == null) return;
      try {
        await widget.store.addOrUpdateProduct(created);
        selectedProduct = created;
        selectedUnit = created.effectivePurchaseUnits.first;
        purchaseProducts = widget.store.products
            .where((product) => product.trackStock && product.isActive)
            .toList();
        applySuggestedSupplierPrice();
        setDialogState(() {});
      } catch (error) {
        if (mounted) showPurchaseError(error.toString());
      }
    }

    Future<void> editPurchaseLine(
        PurchaseItem item, StateSetter setDialogState) async {
      final productMatches =
          purchaseProducts.where((p) => p.id == item.productId).toList();
      if (productMatches.isEmpty) return;
      final product = productMatches.first;
      ProductSaleUnit editUnit = product.effectivePurchaseUnits.firstWhere(
          (unit) => unit.id == item.purchaseUnitId,
          orElse: () => product.effectivePurchaseUnits.first);
      String editCurrency = item.unitCostCurrency;
      final editQtyController =
          TextEditingController(text: _formatQuantity(item.quantity));
      final editCostController = TextEditingController(
          text: (item.originalUnitCost ??
                  fromUsdReferencePrice(
                      item.unitCost, editCurrency, widget.store.storeProfile))
              .toStringAsFixed(editCurrency == 'LBP' ? 0 : 2));
      final updated = await showModalBottomSheet<PurchaseItem>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        isDismissible: false,
        builder: (editContext) => StatefulBuilder(
          builder: (editContext, setEditState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(editContext).bottom),
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(tr.text('edit_purchase_line'),
                                      style: Theme.of(editContext)
                                          .textTheme
                                          .titleLarge)),
                              IconButton(
                                tooltip: tr.text('cancel'),
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(editContext),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: editUnit.id,
                            decoration: InputDecoration(
                                labelText: tr.text('purchase_unit')),
                            items: product.effectivePurchaseUnits
                                .map((unit) => DropdownMenuItem(
                                    value: unit.id,
                                    child: Text(
                                        '${unit.name} Ã— ${_formatQuantity(unit.conversionToBase)}')))
                                .toList(),
                            onChanged: (value) {
                              final matches = product.effectivePurchaseUnits
                                  .where((unit) => unit.id == value)
                                  .toList();
                              if (matches.isNotEmpty) {
                                setEditState(() => editUnit = matches.first);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: editQtyController,
                              decoration: InputDecoration(
                                  labelText: tr.text('quantity')),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true)),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: editCostController,
                              decoration: InputDecoration(
                                  labelText: tr.text('unit_cost')),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: editCurrency,
                            decoration:
                                InputDecoration(labelText: tr.text('currency')),
                            items: const [
                              DropdownMenuItem(
                                  value: 'USD', child: Text('USD')),
                              DropdownMenuItem(value: 'LBP', child: Text('LBP'))
                            ],
                            onChanged: (value) => setEditState(
                                () => editCurrency = value ?? 'USD'),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                  child: TextButton(
                                      onPressed: () =>
                                          Navigator.pop(editContext),
                                      child: Text(tr.text('cancel')))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    final qty = double.tryParse(
                                            editQtyController.text.trim()) ??
                                        0;
                                    final enteredCost = double.tryParse(
                                            editCostController.text.trim()) ??
                                        -1;
                                    if (qty <= 0 ||
                                        enteredCost < 0 ||
                                        editUnit.conversionToBase <= 0) {
                                      return;
                                    }
                                    if (!product.allowsDecimalQuantity &&
                                        qty % 1 != 0) {
                                      return;
                                    }
                                    Navigator.pop(
                                        editContext,
                                        PurchaseItem(
                                          productId: product.id,
                                          productName: product.name,
                                          quantity: qty,
                                          purchaseUnitId: editUnit.id,
                                          purchaseUnitName: editUnit.name,
                                          conversionToBase:
                                              editUnit.conversionToBase,
                                          unitCost: toUsdReferencePrice(
                                              enteredCost,
                                              editCurrency,
                                              widget.store.storeProfile),
                                          originalUnitCost: enteredCost,
                                          unitCostCurrency: editCurrency,
                                          exchangeRateAtEntry: widget
                                              .store.storeProfile.usdToLbpRate,
                                        ));
                                  },
                                  child: Text(tr.text('save')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      editQtyController.dispose();
      editCostController.dispose();
      if (updated != null) {
        final index = items.indexOf(item);
        if (index >= 0) setDialogState(() => items[index] = updated);
      }
    }

    Future<void> updateSupplierPricesFromItemsIfNeeded(
        BuildContext promptContext, List<PurchaseItem> purchaseItems) async {
      if (supplierId.trim().isEmpty || purchaseItems.isEmpty) return;
      final latestByProduct = <String, PurchaseItem>{};
      for (final item in purchaseItems) {
        latestByProduct[item.productId] = item;
      }
      final updates = <SupplierProductPrice>[];
      for (final item in latestByProduct.values) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        final existing = widget.store.supplierProductPriceFor(
            productId: productId, supplierId: supplierId);
        final newCurrency =
            item.unitCostCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
        final newBaseCost =
            newCurrency == 'LBP' && item.originalUnitCost != null
                ? item.originalUnitCost! /
                    (item.conversionToBase <= 0 ? 1 : item.conversionToBase)
                : item.unitCostPerBase;
        final hasChanged = existing == null ||
            (existing.cost - newBaseCost).abs() > 0.0001 ||
            existing.currency.toUpperCase() != newCurrency;
        if (!hasChanged) continue;
        updates.add(SupplierProductPrice(
          id: existing?.id ?? '',
          productId: productId,
          supplierId: supplierId,
          cost: newBaseCost,
          currency: newCurrency,
          isPreferred: existing?.isPreferred ??
              widget.store.supplierProductPricesForProduct(productId).isEmpty,
          supplierSku: existing?.supplierSku ?? '',
          minOrderQty: existing?.minOrderQty,
          leadTimeDays: existing?.leadTimeDays,
          notes: existing?.notes ?? '',
          priceHistory: existing?.priceHistory ?? const [],
          createdAt: existing?.createdAt,
          updatedAt: DateTime.now(),
          deviceId: existing?.deviceId ?? '',
          syncStatus: existing?.syncStatus ?? 'pending',
          storeId: existing?.storeId ?? '',
          branchId: existing?.branchId ?? '',
          version: existing?.version ?? 1,
          lastModifiedByDeviceId: existing?.lastModifiedByDeviceId ?? '',
        ));
      }
      if (updates.isEmpty) return;
      final shouldUpdate = await showDialog<bool>(
        context: promptContext,
        builder: (context) => AlertDialog(
          title: Text(tr.text('update_supplier_prices')),
          content: Text(tr.text('update_supplier_prices_desc')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr.text('no'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr.text('yes'))),
          ],
        ),
      );
      if (shouldUpdate != true) return;
      for (final price in updates) {
        await widget.store.addOrUpdateSupplierProductPrice(price);
      }
    }

    void addPurchaseLine(Product product, ProductSaleUnit unit, double qty,
        double enteredCost, String currency, StateSetter setDialogState) {
      if (qty <= 0) {
        showPurchaseError(tr.text('invalid_purchase_quantity'));
        return;
      }
      if (enteredCost < 0) {
        showPurchaseError(tr.text('unit_cost_required'));
        return;
      }
      if (unit.conversionToBase <= 0) {
        showPurchaseError(tr.text('invalid_purchase_unit_conversion'));
        return;
      }
      if (!product.allowsDecimalQuantity && qty % 1 != 0) {
        showPurchaseError(tr.text('countable_whole_quantity_required'));
        return;
      }
      final cost =
          toUsdReferencePrice(enteredCost, currency, widget.store.storeProfile);
      items.add(PurchaseItem(
        productId: product.id,
        productName: product.name,
        quantity: qty,
        purchaseUnitId: unit.id,
        purchaseUnitName: unit.name,
        conversionToBase: unit.conversionToBase,
        unitCost: cost,
        originalUnitCost: enteredCost,
        unitCostCurrency: currency,
        exchangeRateAtEntry: widget.store.storeProfile.usdToLbpRate,
      ));
      setDialogState(() {});
    }

    void addSelectedPurchaseLine(StateSetter setDialogState) {
      final product = selectedProduct;
      final unit = selectedUnit;
      if (product == null || unit == null) return;
      final qty = double.tryParse(qtyController.text.trim()) ?? 0;
      final enteredCost = double.tryParse(costController.text.trim()) ?? -1;
      addPurchaseLine(
          product, unit, qty, enteredCost, costCurrency, setDialogState);
    }

    ({Product product, ProductSaleUnit unit})? findPurchaseProductByBarcode(
        String rawCode) {
      final code = rawCode.trim();
      if (code.isEmpty) return null;
      for (final product in purchaseProducts) {
        final unitMatch = product.purchaseUnitForBarcode(code);
        if (unitMatch != null) return (product: product, unit: unitMatch);
        if (product.code.trim() == code || product.barcode.trim() == code) {
          return (product: product, unit: product.effectivePurchaseUnits.first);
        }
      }
      return null;
    }

    Future<void> choosePurchaseProduct(StateSetter setDialogState,
        {bool scanFirst = false}) async {
      if (scanFirst) {
        final code = await _scanBarcodeWithCamera();
        if (code == null) return;
        final match = findPurchaseProductByBarcode(code);
        if (match == null) {
          BarcodeFeedbackService.playError(force: true);
          showPurchaseError(tr.text('barcode_not_registered_purchase'));
          return;
        }
        selectedProduct = match.product;
        selectedUnit = match.unit;
        productSearchController.text = match.product.name;
        applySuggestedSupplierPrice();
        BarcodeFeedbackService.play(force: true);
        setDialogState(() {});
        return;
      }

      final pickerController =
          TextEditingController(text: productSearchController.text.trim());
      var pickerQuery = pickerController.text.trim();
      final picked =
          await showModalBottomSheet<({Product product, ProductSaleUnit unit})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (pickerContext) => StatefulBuilder(
          builder: (pickerContext, setPickerState) {
            final matchesFuture =
                _resolvePurchaseSearchProducts(purchaseProducts, pickerQuery);
            final height = MediaQuery.sizeOf(pickerContext).height * 0.82;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(pickerContext).bottom),
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: height,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(tr.text('search_product'),
                                      style: Theme.of(pickerContext)
                                          .textTheme
                                          .titleLarge)),
                              IconButton(
                                tooltip: tr.text('cancel'),
                                onPressed: () => Navigator.pop(pickerContext),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: TextField(
                            controller: pickerController,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: tr.text('search_product'),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                tooltip: tr.text('scan_with_camera'),
                                icon: const Icon(Icons.camera_alt_outlined),
                                onPressed: () async {
                                  final code = await _scanBarcodeWithCamera();
                                  if (code == null) return;
                                  final match =
                                      findPurchaseProductByBarcode(code);
                                  if (match == null) {
                                    BarcodeFeedbackService.playError(
                                        force: true);
                                    showPurchaseError(tr.text(
                                        'barcode_not_registered_purchase'));
                                    return;
                                  }
                                  if (pickerContext.mounted) {
                                    Navigator.pop(pickerContext, match);
                                  }
                                },
                              ),
                            ),
                            onChanged: (value) =>
                                setPickerState(() => pickerQuery = value),
                          ),
                        ),
                        Expanded(
                          child: FutureBuilder<List<Product>>(
                            future: matchesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator.adaptive(),
                                );
                              }
                              final matches =
                                  snapshot.data ?? const <Product>[];
                              if (matches.isEmpty) {
                                return Center(
                                    child: Text(tr.text('no_products')));
                              }
                              return ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                itemCount: matches.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = matches[index];
                                  final unit =
                                      product.effectivePurchaseUnits.first;
                                  final configuredPrice = supplierId.isEmpty
                                      ? null
                                      : widget.store.supplierProductPriceFor(
                                          productId: product.id,
                                          supplierId: supplierId);
                                  final subtitleParts = <String>[
                                    if (product.code.trim().isNotEmpty)
                                      product.code.trim(),
                                    if (product.barcode.trim().isNotEmpty)
                                      product.barcode.trim(),
                                    '${tr.text('stock')}: ${_formatQuantity(product.stock)}',
                                    if (configuredPrice != null)
                                      '${tr.text('supplier_price')}: ${formatCurrency(configuredPrice.cost, currency: configuredPrice.currency)}',
                                  ];
                                  return ListTile(
                                    leading:
                                        const Icon(Icons.inventory_2_outlined),
                                    title: Text(product.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(subtitleParts.join(' • '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.pop(pickerContext,
                                        (product: product, unit: unit)),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add_box_outlined),
                            label: Text(tr.text('add_product')),
                            onPressed: () async {
                              Navigator.pop(pickerContext);
                              await createQuickProduct(setDialogState);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      pickerController.dispose();
      if (picked == null) return;
      selectedProduct = picked.product;
      selectedUnit = picked.unit;
      productSearchController.text = picked.product.name;
      applySuggestedSupplierPrice();
      setDialogState(() {});
    }

    Future<void> savePurchaseFromDialog(BuildContext dialogContext) async {
      if (items.isEmpty) return;
      if (!(formKey.currentState?.validate() ?? false)) return;
      try {
        final purchaseItems = List<PurchaseItem>.of(items);
        final total =
            items.fold<double>(0, (sum, item) => sum + item.lineTotal);
        final paidAmount = paymentStatus == 'partial'
            ? (double.tryParse(paidAmountController.text.trim()) ?? 0)
            : null;
        if (paymentStatus == 'partial' &&
            (paidAmount == null || paidAmount <= 0 || paidAmount > total)) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(content: Text(tr.text('invalid_paid_amount'))));
          return;
        }
        await widget.store.createPurchase(
            supplierId: supplierId,
            supplierName: supplierName,
            items: purchaseItems,
            receiveNow: receiveNow,
            paymentStatus: paymentStatus,
            paymentMethod: paymentMethod,
            paidAmount: paidAmount);
        if (dialogContext.mounted) {
          await updateSupplierPricesFromItemsIfNeeded(
              dialogContext, purchaseItems);
        }
        if (dialogContext.mounted) Navigator.pop(dialogContext);
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
              content: Text(template == null
                  ? tr.text('purchase_saved')
                  : tr.text('duplicate_purchase_saved_as_draft'))),
        );
        setState(() {});
      } catch (error) {
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }

    Future<void> cancelPurchaseDialog(BuildContext dialogContext) async {
      if (await confirmDiscardIfNeeded(dialogContext) &&
          dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
    }

    KeyEventResult handlePurchaseDialogShortcutKey(KeyEvent event,
        BuildContext dialogContext, StateSetter setDialogState) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final keyName =
          SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
      if (keyName == null) return KeyEventResult.ignored;
      final action =
          SaleShortcutSettings.load().purchaseDialogActionForKey(keyName);
      if (action == null) return KeyEventResult.ignored;
      switch (action) {
        case PurchaseDialogShortcutAction.chooseProduct:
          choosePurchaseProduct(setDialogState);
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.addLine:
          addSelectedPurchaseLine(setDialogState);
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.savePurchase:
          savePurchaseFromDialog(dialogContext);
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.cancelPurchase:
          cancelPurchaseDialog(dialogContext);
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.toggleReceiveNow:
          setDialogState(() => receiveNow = !receiveNow);
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.focusQuantity:
          qtyFocusNode.requestFocus();
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.focusCost:
          costFocusNode.requestFocus();
          return KeyEventResult.handled;
        case PurchaseDialogShortcutAction.focusPaidAmount:
          paidAmountFocusNode.requestFocus();
          return KeyEventResult.handled;
      }
    }

    BuildContext? activePurchaseDialogContext;
    StateSetter? activePurchaseDialogSetState;
    bool handlePurchaseDialogHardwareShortcut(KeyEvent event) {
      final dialogContext = activePurchaseDialogContext;
      final setDialogState = activePurchaseDialogSetState;
      if (dialogContext == null ||
          setDialogState == null ||
          ModalRoute.of(dialogContext)?.isCurrent != true) {
        return false;
      }
      return handlePurchaseDialogShortcutKey(
              event, dialogContext, setDialogState) ==
          KeyEventResult.handled;
    }

    HardwareKeyboard.instance.addHandler(handlePurchaseDialogHardwareShortcut);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        isDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            activePurchaseDialogContext = dialogContext;
            activePurchaseDialogSetState = setDialogState;
            final total =
                items.fold<double>(0, (sum, item) => sum + item.lineTotal);
            final units = selectedProduct?.effectivePurchaseUnits ??
                const <ProductSaleUnit>[];
            if (selectedUnit != null &&
                !units.any((unit) => unit.id == selectedUnit!.id)) {
              selectedUnit = units.isNotEmpty ? units.first : null;
              applySuggestedSupplierPrice();
            }
            final dialogWidth = VentioResponsive.modalMaxWidth(context, 1220);
            final dialogHeight = MediaQuery.sizeOf(context).height * 0.88;
            return Focus(
              focusNode: dialogShortcutFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) => handlePurchaseDialogShortcutKey(
                  event, dialogContext, setDialogState),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: dialogWidth, maxHeight: dialogHeight),
                    child: Material(
                      clipBehavior: Clip.antiAlias,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(
                                        template == null
                                            ? tr.text('new_purchase')
                                            : tr.text(
                                                'duplicate_purchase_draft'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall)),
                                IconButton(
                                  tooltip: tr.text('cancel'),
                                  onPressed: () =>
                                      cancelPurchaseDialog(dialogContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child:
                                _buildPurchaseDialogShortcutGuide(context, tr),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.all(
                                  VentioResponsive.pagePadding(context)),
                              child: Form(
                                key: formKey,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final desktopLayout =
                                        constraints.maxWidth >= 900;
                                    final gap = VentioResponsive.gap(context);

                                    Widget sectionCard(
                                        {required String title,
                                        required IconData icon,
                                        required List<Widget> children}) {
                                      return Card(
                                        elevation: 0,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.35),
                                        child: Padding(
                                          padding: VentioResponsive.cardInsets(
                                              context),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(icon, size: 20),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                      child: Text(title,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .titleMedium)),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              ...children,
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    Widget supplierSection() {
                                      return sectionCard(
                                        title: tr.text('purchase_details'),
                                        icon: Icons.receipt_long_outlined,
                                        children: [
                                          if (purchaseProducts.isEmpty) ...[
                                            Text(tr.text(
                                                'no_stock_tracked_products')),
                                            SizedBox(height: gap),
                                          ],
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  initialValue:
                                                      supplierId.isEmpty
                                                          ? null
                                                          : supplierId,
                                                  decoration: InputDecoration(
                                                      labelText:
                                                          tr.text('supplier')),
                                                  items: widget.store.suppliers
                                                      .map((supplier) =>
                                                          DropdownMenuItem(
                                                              value:
                                                                  supplier.id,
                                                              child: Text(
                                                                  supplier
                                                                      .name)))
                                                      .toList(),
                                                  onChanged: (value) {
                                                    final matches = widget
                                                        .store.suppliers
                                                        .where((s) =>
                                                            s.id == value)
                                                        .toList();
                                                    final supplier =
                                                        matches.isEmpty
                                                            ? null
                                                            : matches.first;
                                                    supplierId =
                                                        supplier?.id ?? '';
                                                    supplierName =
                                                        supplier?.name ?? '';
                                                    applySuggestedSupplierPrice();
                                                    setDialogState(() {});
                                                  },
                                                  validator: (_) => supplierId
                                                          .isEmpty
                                                      ? tr.text(
                                                          'supplier_required')
                                                      : null,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton.filledTonal(
                                                tooltip:
                                                    tr.text('add_supplier'),
                                                onPressed: () =>
                                                    createQuickSupplier(
                                                        setDialogState),
                                                icon: const Icon(Icons
                                                    .person_add_alt_1_outlined),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: gap),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            value: receiveNow,
                                            onChanged: (value) =>
                                                setDialogState(
                                                    () => receiveNow = value),
                                            title: Text(tr.text('receive_now')),
                                            subtitle: Text(
                                                tr.text('receive_now_desc')),
                                          ),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            initialValue: paymentStatus,
                                            decoration: InputDecoration(
                                                labelText:
                                                    tr.text('payment_status')),
                                            items: [
                                              DropdownMenuItem(
                                                  value: 'paid',
                                                  child: Text(
                                                      tr.text('cash_paid'))),
                                              DropdownMenuItem(
                                                  value: 'credit',
                                                  child: Text(tr
                                                      .text('credit_unpaid'))),
                                              DropdownMenuItem(
                                                  value: 'partial',
                                                  child: Text(tr.text(
                                                      'partial_payment'))),
                                            ],
                                            onChanged: (value) =>
                                                setDialogState(() =>
                                                    paymentStatus =
                                                        value ?? 'paid'),
                                          ),
                                          if (paymentStatus != 'credit') ...[
                                            const SizedBox(height: 8),
                                            DropdownButtonFormField<String>(
                                              initialValue: paymentMethod,
                                              decoration: InputDecoration(
                                                  labelText: tr
                                                      .text('payment_method')),
                                              items: [
                                                DropdownMenuItem(
                                                    value: 'Cash',
                                                    child: Text(tr
                                                        .text('payment_cash'))),
                                                DropdownMenuItem(
                                                    value: 'Card',
                                                    child: Text(tr
                                                        .text('payment_card'))),
                                                DropdownMenuItem(
                                                    value: 'Wish',
                                                    child: Text(tr
                                                        .text('payment_wish'))),
                                                DropdownMenuItem(
                                                    value: 'Check',
                                                    child: Text(tr.text(
                                                        'payment_check'))),
                                              ],
                                              onChanged: (value) =>
                                                  setDialogState(() =>
                                                      paymentMethod =
                                                          value ?? 'Cash'),
                                            ),
                                          ],
                                          if (paymentStatus == 'partial') ...[
                                            SizedBox(height: gap),
                                            TextFormField(
                                              controller: paidAmountController,
                                              focusNode: paidAmountFocusNode,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      tr.text('paid_amount')),
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              Chip(
                                                  label: Text(
                                                      '${tr.text('status')}: ${receiveNow ? tr.text('received') : tr.text('draft')}')),
                                              Chip(
                                                  label: Text(
                                                      '${tr.text('items')}: ${items.length}')),
                                            ],
                                          ),
                                        ],
                                      );
                                    }

                                    Widget productEntrySection() {
                                      final conversion =
                                          selectedUnitConversionSummary();
                                      final selectedProductTitle =
                                          selectedProduct?.name ??
                                              tr.text('product');
                                      final selectedProductSubtitle =
                                          selectedProduct == null
                                              ? tr.text(
                                                  'scan_purchase_barcode_hint')
                                              : [
                                                  if (selectedProduct!.code
                                                      .trim()
                                                      .isNotEmpty)
                                                    selectedProduct!.code
                                                        .trim(),
                                                  if (selectedProduct!.barcode
                                                      .trim()
                                                      .isNotEmpty)
                                                    selectedProduct!.barcode
                                                        .trim(),
                                                  '${tr.text('stock')}: ${_formatQuantity(selectedProduct!.stock)}',
                                                ].join(' â€¢ ');
                                      return sectionCard(
                                        title: tr.text('add_product'),
                                        icon: Icons.add_box_outlined,
                                        children: [
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            onTap: () => choosePurchaseProduct(
                                                setDialogState),
                                            child: InputDecorator(
                                              decoration: InputDecoration(
                                                labelText:
                                                    tr.text('search_product'),
                                                prefixIcon:
                                                    const Icon(Icons.search),
                                                suffixIcon: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: tr.text(
                                                          'scan_with_camera'),
                                                      onPressed: () =>
                                                          choosePurchaseProduct(
                                                              setDialogState,
                                                              scanFirst: true),
                                                      icon: const Icon(Icons
                                                          .camera_alt_outlined),
                                                    ),
                                                    IconButton(
                                                      tooltip: tr
                                                          .text('add_product'),
                                                      onPressed: () =>
                                                          createQuickProduct(
                                                              setDialogState),
                                                      icon: const Icon(Icons
                                                          .add_box_outlined),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(selectedProductTitle,
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  if (selectedProductSubtitle
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      selectedProductSubtitle,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: gap),
                                          LayoutBuilder(
                                            builder:
                                                (context, fieldConstraints) {
                                              final oneColumn =
                                                  fieldConstraints.maxWidth <
                                                      520;
                                              final unitField =
                                                  DropdownButtonFormField<
                                                      String>(
                                                initialValue: selectedUnit?.id,
                                                decoration: InputDecoration(
                                                    labelText: tr
                                                        .text('purchase_unit')),
                                                items: units
                                                    .map((unit) => DropdownMenuItem(
                                                        value: unit.id,
                                                        child: Text(
                                                            '${unit.name} Ã— ${_formatQuantity(unit.conversionToBase)}')))
                                                    .toList(),
                                                onChanged: (value) {
                                                  final matches = units
                                                      .where((unit) =>
                                                          unit.id == value)
                                                      .toList();
                                                  selectedUnit = matches.isEmpty
                                                      ? null
                                                      : matches.first;
                                                  applySuggestedSupplierPrice();
                                                  setDialogState(() {});
                                                },
                                              );
                                              final qtyField = TextFormField(
                                                controller: qtyController,
                                                focusNode: qtyFocusNode,
                                                decoration: InputDecoration(
                                                    labelText:
                                                        tr.text('quantity')),
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                onChanged: (_) =>
                                                    setDialogState(() {}),
                                              );
                                              final costField = TextFormField(
                                                controller: costController,
                                                focusNode: costFocusNode,
                                                decoration: InputDecoration(
                                                    labelText:
                                                        tr.text('unit_cost'),
                                                    helperText:
                                                        priceHintForSelectedProduct()
                                                                .isEmpty
                                                            ? null
                                                            : priceHintForSelectedProduct()),
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                              );
                                              final currencyField =
                                                  DropdownButtonFormField<
                                                      String>(
                                                initialValue: costCurrency,
                                                decoration: InputDecoration(
                                                    labelText:
                                                        tr.text('currency')),
                                                items: const [
                                                  DropdownMenuItem(
                                                      value: 'USD',
                                                      child: Text('USD')),
                                                  DropdownMenuItem(
                                                      value: 'LBP',
                                                      child: Text('LBP')),
                                                ],
                                                onChanged: (value) =>
                                                    setDialogState(() =>
                                                        costCurrency =
                                                            value ?? 'USD'),
                                              );
                                              if (oneColumn) {
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    unitField,
                                                    SizedBox(height: gap),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                            child: qtyField),
                                                        SizedBox(width: gap),
                                                        SizedBox(
                                                            width: 120,
                                                            child:
                                                                currencyField),
                                                      ],
                                                    ),
                                                    SizedBox(height: gap),
                                                    costField,
                                                  ],
                                                );
                                              }
                                              return Wrap(
                                                spacing: 12,
                                                runSpacing: 12,
                                                children: [
                                                  SizedBox(
                                                      width: 220,
                                                      child: unitField),
                                                  SizedBox(
                                                      width: 120,
                                                      child: qtyField),
                                                  SizedBox(
                                                      width: 190,
                                                      child: costField),
                                                  SizedBox(
                                                      width: 120,
                                                      child: currencyField),
                                                ],
                                              );
                                            },
                                          ),
                                          if (conversion.isNotEmpty) ...[
                                            SizedBox(height: gap),
                                            Align(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: Chip(
                                                    avatar: const Icon(
                                                        Icons.compare_arrows,
                                                        size: 18),
                                                    label: Text(conversion))),
                                          ],
                                          SizedBox(height: gap),
                                          FilledButton.icon(
                                            onPressed: selectedProduct ==
                                                        null ||
                                                    selectedUnit == null
                                                ? null
                                                : () => addSelectedPurchaseLine(
                                                    setDialogState),
                                            icon: const Icon(Icons.add),
                                            label: Text(tr.text(
                                                'add_product_to_purchase')),
                                          ),
                                        ],
                                      );
                                    }

                                    Widget lineActions(PurchaseItem item) =>
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                                tooltip: tr.text('edit'),
                                                onPressed: () =>
                                                    editPurchaseLine(
                                                        item, setDialogState)),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                tooltip: tr.text('delete'),
                                                onPressed: () => setDialogState(
                                                    () => items.remove(item))),
                                          ],
                                        );

                                    Widget purchaseLinesSection() {
                                      if (items.isEmpty) {
                                        return sectionCard(
                                          title: tr.text('purchase_invoice'),
                                          icon: Icons.table_chart_outlined,
                                          children: [
                                            Text(tr.text('no_items_added'))
                                          ],
                                        );
                                      }
                                      final table = SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columns: [
                                            DataColumn(
                                                label:
                                                    Text(tr.text('product'))),
                                            DataColumn(
                                                label: Text(tr.text('unit'))),
                                            DataColumn(
                                                label:
                                                    Text(tr.text('quantity'))),
                                            DataColumn(
                                                label:
                                                    Text(tr.text('unit_cost'))),
                                            DataColumn(
                                                label: Text(tr.text('total'))),
                                            DataColumn(
                                                label:
                                                    Text(tr.text('actions'))),
                                          ],
                                          rows: items
                                              .map((item) => DataRow(cells: [
                                                    DataCell(SizedBox(
                                                        width: 180,
                                                        child: Text(
                                                            item.productName,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis))),
                                                    DataCell(Text(
                                                        item.purchaseUnitName)),
                                                    DataCell(Text(
                                                        _formatQuantity(
                                                            item.quantity))),
                                                    DataCell(Text(formatCurrency(
                                                        item.originalUnitCost ??
                                                            item.unitCost,
                                                        currency: item
                                                            .unitCostCurrency))),
                                                    DataCell(Text(
                                                        formatUsdReferenceAmount(
                                                            item.lineTotal,
                                                            widget.store
                                                                .storeProfile))),
                                                    DataCell(lineActions(item)),
                                                  ]))
                                              .toList(),
                                        ),
                                      );
                                      final cards = Column(
                                        children: items
                                            .map((item) => Card(
                                                  margin: const EdgeInsets.only(
                                                      bottom: 8),
                                                  child: ListTile(
                                                    title:
                                                        Text(item.productName),
                                                    subtitle: Text(
                                                        '${unitConversionSummary(item)} â€¢ ${formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency)} â€¢ ${formatUsdReferenceAmount(item.lineTotal, widget.store.storeProfile)}'),
                                                    trailing: lineActions(item),
                                                  ),
                                                ))
                                            .toList(),
                                      );
                                      return sectionCard(
                                        title: tr.text('purchase_invoice'),
                                        icon: Icons.table_chart_outlined,
                                        children: [
                                          desktopLayout ? table : cards
                                        ],
                                      );
                                    }

                                    Widget summarySection() {
                                      return Card(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        child: Padding(
                                          padding: VentioResponsive.cardInsets(
                                              context),
                                          child: Wrap(
                                            spacing: 20,
                                            runSpacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            alignment:
                                                WrapAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                  '${tr.text('supplier')}: ${supplierName.isEmpty ? '-' : supplierName}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium),
                                              Text(
                                                  '${tr.text('items')}: ${items.length}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium),
                                              Text(
                                                  '${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    final leftPanel = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        supplierSection(),
                                        SizedBox(height: gap),
                                        productEntrySection()
                                      ],
                                    );
                                    final rightPanel = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        purchaseLinesSection(),
                                        SizedBox(height: gap),
                                        summarySection()
                                      ],
                                    );

                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (desktopLayout)
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                  width: 390, child: leftPanel),
                                              SizedBox(width: gap),
                                              Expanded(child: rightPanel),
                                            ],
                                          )
                                        else ...[
                                          leftPanel,
                                          SizedBox(height: gap),
                                          rightPanel,
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              VentioResponsive.pagePadding(context),
                              12,
                              VentioResponsive.pagePadding(context),
                              16,
                            ),
                            child: LayoutBuilder(
                              builder: (context, footerConstraints) {
                                final compactFooter =
                                    footerConstraints.maxWidth < 520;
                                final totalText = Text(
                                  '${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                );
                                final cancelButton = TextButton(
                                  onPressed: () =>
                                      cancelPurchaseDialog(dialogContext),
                                  child: Text(tr.text('cancel')),
                                );
                                final saveButton = FilledButton.icon(
                                  onPressed: items.isEmpty
                                      ? null
                                      : () =>
                                          savePurchaseFromDialog(dialogContext),
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(tr.text('save')),
                                );
                                if (compactFooter) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      totalText,
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(child: cancelButton),
                                          const SizedBox(width: 12),
                                          Expanded(child: saveButton),
                                        ],
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: totalText),
                                    cancelButton,
                                    const SizedBox(width: 12),
                                    saveButton,
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      HardwareKeyboard.instance
          .removeHandler(handlePurchaseDialogHardwareShortcut);
      activePurchaseDialogContext = null;
      activePurchaseDialogSetState = null;
    }
    qtyController.dispose();
    costController.dispose();
    productSearchController.dispose();
    paidAmountController.dispose();
    dialogShortcutFocusNode.dispose();
    qtyFocusNode.dispose();
    costFocusNode.dispose();
    paidAmountFocusNode.dispose();
  }
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
  });

  final Purchase purchase;
  final StoreProfile storeProfile;
  final String Function(DateTime date) formatDate;
  final VoidCallback? onTap,
      onReceive,
      onCancel,
      onDeleteDraft,
      onPermanentDelete,
      onDuplicate;

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
    final statusText = purchase.isReturned
        ? tr.text('returned')
        : purchase.status.toLowerCase() == 'cancelled'
            ? tr.text('cancelled')
            : purchase.isReceived
                ? tr.text('received')
                : tr.text('draft');
    final statusColor = purchase.isReturned
        ? Colors.blueGrey
        : purchase.status.toLowerCase() == 'cancelled'
            ? Colors.red
            : purchase.isReceived
                ? Colors.green
                : Colors.orange;
    final statusIcon = purchase.isReturned
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
        '${purchase.items.length} ${tr.text('items')} â€¢ ${_formatQuantity(purchase.totalUnits)} ${tr.text('units')} â€¢ ${formatDate(purchase.date)}';

    final actionsMenu = PopupMenuButton<String>(
      tooltip: tr.text('actions'),
      onSelected: (value) {
        if (value == 'duplicate') onDuplicate?.call();
        if (value == 'receive') onReceive?.call();
        if (value == 'return') onCancel?.call();
        if (value == 'delete_draft') onDeleteDraft?.call();
        if (value == 'permanent_delete') onPermanentDelete?.call();
      },
      itemBuilder: (context) => [
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
