// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_page.dart';

extension _PurchasesPageStateMethods1 on _PurchasesPageState {
  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _formatQuantity(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

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

  Future<void> _editPurchasesShortcut(
      PurchasesShortcutAction action, AppLocalizations tr) async {
    final settings = SaleShortcutSettings.load();
    final currentKey =
        settings.keyForPurchasesAction(action) ?? SaleShortcutSettings.noneKey;
    final selectedKey = await showShortcutKeyPicker(
      context: context,
      title: tr.text('shortcut_change'),
      currentKey: currentKey,
      noneLabel: tr.text('shortcut_none'),
      cancelLabel: tr.text('cancel'),
      saveLabel: tr.text('save'),
    );
    if (selectedKey == null || !mounted) return;
    if (settings.isPurchasesKeyUsedByAnotherAction(selectedKey, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = settings.copyWithPurchasesActionKey(action, selectedKey);
    await next.save();
    if (mounted) setState(() {});
  }

  Future<void> _editPurchaseDialogShortcut(
      PurchaseDialogShortcutAction action, AppLocalizations tr) async {
    final settings = SaleShortcutSettings.load();
    final currentKey = settings.keyForPurchaseDialogAction(action) ??
        SaleShortcutSettings.noneKey;
    final selectedKey = await showShortcutKeyPicker(
      context: context,
      title: tr.text('shortcut_change'),
      currentKey: currentKey,
      noneLabel: tr.text('shortcut_none'),
      cancelLabel: tr.text('cancel'),
      saveLabel: tr.text('save'),
    );
    if (selectedKey == null || !mounted) return;
    if (settings.isPurchaseDialogKeyUsedByAnotherAction(selectedKey, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = settings.copyWithPurchaseDialogActionKey(action, selectedKey);
    await next.save();
    if (mounted) setState(() {});
  }

  Widget _buildPurchasesShortcutGuide(
      BuildContext context, AppLocalizations tr) {
    return ValueListenableBuilder<int>(
      valueListenable: SaleShortcutSettings.revision,
      builder: (context, _, __) {
        final settings = SaleShortcutSettings.load();
        final chips = <Widget>[];
        for (final action in PurchasesShortcutAction.values) {
          final keyName = settings.keyForPurchasesAction(action);
          if (keyName == null || keyName == SaleShortcutSettings.noneKey) {
            continue;
          }
          chips.add(ShortcutGuideChip(
            keyName: keyName,
            label: tr.text(action.labelKey),
            onPressed: () => _editPurchasesShortcut(action, tr),
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
      },
    );
  }

  Widget _buildPurchaseDialogShortcutGuide(
      BuildContext context, AppLocalizations tr) {
    return ValueListenableBuilder<int>(
      valueListenable: SaleShortcutSettings.revision,
      builder: (context, _, __) {
        final settings = SaleShortcutSettings.load();
        final chips = <Widget>[];
        for (final action in PurchaseDialogShortcutAction.values) {
          final keyName = settings.keyForPurchaseDialogAction(action);
          if (keyName == null || keyName == SaleShortcutSettings.noneKey) {
            continue;
          }
          chips.add(Padding(
            padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
            child: ShortcutGuideChip(
              keyName: keyName,
              label: tr.text(action.labelKey),
              onPressed: () => _editPurchaseDialogShortcut(action, tr),
            ),
          ));
        }
        if (chips.isEmpty) return const SizedBox.shrink();
        return Wrap(children: chips);
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
                  icon: const Icon(Icons.assignment_return_outlined),
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
                            ? () =>
                                _openPurchaseDialog(context, template: purchase)
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
                  ),
          ),
          if (result.hasMore) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                onPressed: () => _loadMorePurchases(totalCount),
                icon: const Icon(Icons.expand_more),
                label: Text(tr.text('load_more')),
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
      final matches = widget.store.purchases.where((item) => item.id == id);
      final purchase = matches.isEmpty ? null : matches.first;
      final allocationsByLine = <int, List<BatchAllocation>>{};
      if (purchase != null) {
        for (var lineIndex = 0;
            lineIndex < purchase.items.length;
            lineIndex += 1) {
          final item = purchase.items[lineIndex];
          final products =
              widget.store.products.where((p) => p.id == item.productId);
          final product = products.isEmpty ? null : products.first;
          if (product == null || !product.expiryTrackingEnabled) continue;
          final existing = item.batchAllocations.length == 1 &&
                  (item.batchAllocations.first.quantity - item.baseQuantity)
                          .abs() <=
                      0.000001 &&
                  item.batchAllocations.first.expirationDate != null
              ? item.batchAllocations.first
              : null;
          if (existing != null) {
            allocationsByLine[lineIndex] = <BatchAllocation>[existing];
            continue;
          }
          // Legacy drafts may predate line-level expiry capture. Prompt only
          // for those rows; normal Phase-2 drafts already carry the date.
          final allocations = await _promptBatchAllocations(
            context,
            product: product,
            quantity: item.baseQuantity,
          );
          if (allocations == null) return;
          allocationsByLine[lineIndex] = allocations;
        }
      }
      await widget.store.receivePurchase(
        id,
        batchAllocationsByLine: allocationsByLine,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('purchase_received'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizedErrorText(AppLocalizations.of(context), error))));
    }
  }

  Future<List<BatchAllocation>?> _promptBatchAllocations(
    BuildContext context, {
    required Product product,
    required double quantity,
  }) async {
    final tr = AppLocalizations.of(context);
    if (!product.expiryTrackingEnabled) {
      return <BatchAllocation>[
        BatchAllocation(batchId: '', quantity: quantity),
      ];
    }
    final batchNumberController = TextEditingController();
    DateTime? expiry = product.defaultShelfLifeDays > 0
        ? DateTime.now().add(Duration(days: product.defaultShelfLifeDays))
        : null;
    final allocation = await showDialog<BatchAllocation>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('${tr.text('expiration_date')} — ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '${tr.text('batch_quantity')}: ${_formatQuantity(quantity)}'),
              const SizedBox(height: 12),
              TextField(
                controller: batchNumberController,
                decoration: InputDecoration(labelText: tr.text('batch_number')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(expiry == null
                    ? tr.text('expiration_date')
                    : MaterialLocalizations.of(dialogContext)
                        .formatMediumDate(expiry!)),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: dialogContext,
                    initialDate: expiry ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 36500)),
                  );
                  if (value != null) setDialogState(() => expiry = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              key: const ValueKey('PurchaseBatchSaveButton'),
              onPressed: () {
                if (expiry == null) return;
                Navigator.pop(
                  dialogContext,
                  BatchAllocation(
                    batchId: '',
                    quantity: quantity,
                    supplierBatchNumber: batchNumberController.text.trim(),
                    expirationDate: expiry,
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );
    batchNumberController.dispose();
    if (allocation == null) return null;
    return <BatchAllocation>[allocation];
  }
}
