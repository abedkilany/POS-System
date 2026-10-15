// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageDesktopLayout on _SalesPageState {
  Widget _buildDesktopSalesLayout(BuildContext context, AppLocalizations tr,
      List<Product> products, double pagePadding) {
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: pagePadding, vertical: 4),
        child: Column(children: [
          AppSectionHeader(
              title: tr.text('pos_terminal'),
              subtitle: tr.text('pos_terminal_desc'),
              compact: true,
              action: Wrap(spacing: 8, runSpacing: 8, children: [
                if (widget.store.security.canSell)
                  _buildSaleShiftActionButton(context, tr),
                OutlinedButton.icon(
                    onPressed: _refreshingProductData
                        ? null
                        : () => _refreshProductData(tr),
                    icon: _refreshingProductData
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: Text(tr.text('refresh'))),
                if (_legacyShiftButtonVisible)
                  OutlinedButton.icon(
                      onPressed: widget.store.security.canSell
                          ? _showSaleShiftQuickAction
                          : null,
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: Text(tr.text('manage_shift'))),
                OutlinedButton.icon(
                    onPressed: _showInvoicesSheet,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(tr.text('recent_invoices'))),
                OutlinedButton.icon(
                    onPressed:
                        widget.store.security.hasPermission(AppPermission.salesCancel)
                            ? () => _openSaleReturnDialog(context)
                            : null,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(tr.text('new_sales_return')))
              ])),
          const SizedBox(height: 2),
          Expanded(
              child: Column(children: [
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final minimumQuickWidth = math.min(280.0, totalWidth * 0.35);
              final maximumQuickWidth = math.max(minimumQuickWidth,
                  math.min(totalWidth * 0.65, totalWidth - 420));
              final quickWidth = (totalWidth * _quickPanelFraction)
                  .clamp(minimumQuickWidth, maximumQuickWidth)
                  .toDouble();
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: _buildCurrentSalePanel(context, tr, products,
                            showTotalBar: false)),
                    const SizedBox(width: 4),
                    Tooltip(
                        message: tr.text('quick_panel_resize_hint'),
                        child: MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) =>
                                    _resizeQuickProductPanel(
                                        totalWidth, details.delta.dx),
                                onHorizontalDragEnd: (_) {
                                  unawaited(LocalDatabaseService.setString(
                                      _SalesPageState
                                          ._quickPanelFractionStorageKey,
                                      _quickPanelFraction.toString()));
                                },
                                child: SizedBox(
                                    width: 16,
                                    child: Center(
                                        child: Container(
                                            width: 4,
                                            decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outlineVariant,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        8)))))))),
                    const SizedBox(width: 4),
                    SizedBox(
                        width: quickWidth,
                        child:
                            _buildQuickProductGridPanel(context, tr, products))
                  ]);
            })),
            const SizedBox(height: 6),
            _buildSaleTotalBar(context, tr)
          ]))
        ]));
  }

  Widget _buildCurrentSalePanel(
      BuildContext context, AppLocalizations tr, List<Product> products,
      {bool showTotalBar = true}) {
    return Card(
        child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBarcodeStation(context, tr, products: products),
                  const SizedBox(height: 12),
                  Expanded(
                      child: _buildCart(context, tr,
                          showTotals: false, showActions: false)),
                  if (showTotalBar) ...[
                    const SizedBox(height: 12),
                    _buildSaleTotalBar(context, tr)
                  ]
                ])));
  }

  Widget _buildQuickProductGridPanel(
      BuildContext context, AppLocalizations tr, List<Product> products) {
    _ensureQuickPages(products, tr);
    final page = _quickPages[
        _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt()];
    final visibleSlotIndexes = _quickVisibleSlotIndexes(page);
    return Card(
        child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(tr.text('quick_product_grid'),
                            style: Theme.of(context).textTheme.titleLarge)),
                    _buildQuickTileSizeButton(context, tr),
                    if (_quickGridEditMode) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                          onPressed: _cancelQuickGridEditing,
                          icon: const Icon(Icons.close),
                          label: Text(tr.text('cancel'))),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                          onPressed: _saveQuickGridEditing,
                          icon: const Icon(Icons.check),
                          label: Text(tr.text('save')))
                    ] else
                      TextButton.icon(
                          onPressed: _startQuickGridEditing,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(tr.text('edit_layout')))
                  ]),
                  const SizedBox(height: 8),
                  _buildSalePriceTypeSelector(context, tr),
                  const SizedBox(height: 8),
                  SizedBox(
                      height: 42,
                      child: Row(children: [
                        Expanded(
                            child: _quickGridEditMode
                                ? ReorderableListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    buildDefaultDragHandles: false,
                                    itemCount: _quickPages.length,
                                    onReorderItem: _moveQuickPage,
                                    proxyDecorator: (child, _, __) => Material(
                                        elevation: 6,
                                        borderRadius: BorderRadius.circular(24),
                                        child: child),
                                    itemBuilder: (context, index) {
                                      final selected =
                                          index == _selectedQuickPageIndex;
                                      return Padding(
                                          key: ValueKey(
                                              'quick_page_${index}_${_quickPages[index].name}'),
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  end: 8),
                                          child: ReorderableDragStartListener(
                                              index: index,
                                              child: InputChip(
                                                  avatar: const Icon(
                                                      Icons.drag_indicator,
                                                      size: 18),
                                                  label: Row(
                                                      mainAxisSize: MainAxisSize
                                                          .min,
                                                      children: [
                                                        ConstrainedBox(
                                                            constraints:
                                                                const BoxConstraints(
                                                                    maxWidth:
                                                                        120),
                                                            child: Text(
                                                                _quickPages[
                                                                        index]
                                                                    .name,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis)),
                                                        const SizedBox(
                                                            width: 4),
                                                        const Icon(
                                                            Icons.edit_outlined,
                                                            size: 16)
                                                      ]),
                                                  selected: selected,
                                                  onSelected: (_) {
                                                    if (selected) {
                                                      _renameQuickPage(index);
                                                    } else {
                                                      setState(() =>
                                                          _selectedQuickPageIndex =
                                                              index);
                                                    }
                                                  },
                                                  deleteIcon:
                                                      _quickPages.length > 1
                                                          ? const Icon(
                                                              Icons.close,
                                                              size: 18)
                                                          : null,
                                                  onDeleted: _quickPages
                                                              .length >
                                                          1
                                                      ? () => _deleteQuickPage(
                                                          index)
                                                      : null)));
                                    })
                                : ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _quickPages.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final selected =
                                          index == _selectedQuickPageIndex;
                                      return InputChip(
                                          label: Text(_quickPages[index].name),
                                          selected: selected,
                                          onSelected: (_) => setState(() =>
                                              _selectedQuickPageIndex = index));
                                    })),
                        if (_quickGridEditMode) ...[
                          const SizedBox(width: 8),
                          ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: Text(tr.text('page')),
                              onPressed: _addQuickPage)
                        ]
                      ])),
                  const SizedBox(height: 12),
                  Expanded(
                      child: visibleSlotIndexes.isEmpty
                          ? Center(child: Text(tr.text('no_products')))
                          : LayoutBuilder(builder: (context, constraints) {
                              final crossAxisCount =
                                  _quickTileColumnCount(constraints.maxWidth);
                              return GridView.builder(
                                  itemCount: visibleSlotIndexes.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: 1),
                                  itemBuilder: (context, visibleIndex) {
                                    final slotIndex =
                                        visibleSlotIndexes[visibleIndex];
                                    final slot = page.slots[slotIndex];
                                    final product = slot.productId == null
                                        ? null
                                        : _productById(slot.productId!);
                                    final isEmpty = product == null;
                                    final child = _buildQuickProductTile(
                                        context,
                                        tr,
                                        page,
                                        slotIndex,
                                        slot,
                                        product,
                                        isEmpty);
                                    if (!_quickGridEditMode) return child;
                                    final target = DragTarget<int>(
                                        onWillAcceptWithDetails: (details) =>
                                            details.data != slotIndex,
                                        onAcceptWithDetails: (details) =>
                                            _moveQuickSlot(
                                                details.data, slotIndex),
                                        builder: (_, candidateData, ___) {
                                          if (candidateData.isEmpty) {
                                            return child;
                                          }
                                          return DecoratedBox(
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      width: 2)),
                                              child: child);
                                        });
                                    if (isEmpty) return target;
                                    return LongPressDraggable<int>(
                                        data: slotIndex,
                                        feedback: Material(
                                            elevation: 6,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: SizedBox(
                                                width: 150,
                                                height: 120,
                                                child: child)),
                                        childWhenDragging: Opacity(
                                            opacity: 0.35, child: child),
                                        child: target);
                                  });
                            }))
                ])));
  }
}
