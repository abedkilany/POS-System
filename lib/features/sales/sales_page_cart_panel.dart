part of 'sales_page.dart';

extension _SalesPageCartPanel on _SalesPageState {
  Widget _buildCart(BuildContext context, AppLocalizations tr,
      {bool compactActions = false,
      bool showTotals = true,
      bool showActions = true,
      bool expandCartList = true}) {
    Widget cartList(
        {required bool shrinkWrap, required ScrollPhysics? physics}) {
      return ListView.separated(
          shrinkWrap: shrinkWrap,
          primary: false,
          physics: physics,
          itemCount: _cart.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _cart[index];
            var editedQuantity = _formatQuantity(item.quantity);
            final itemKey = _cartItemKeys.putIfAbsent(index, GlobalKey.new);
            final isSelected = index == _selectedCartIndex;
            final isPendingDelete = index == _pendingDeleteCartIndex;
            final rowColor = isPendingDelete
                ? Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.65)
                : item.needsAutoCorrection
                    ? Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.55)
                    : isSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.65)
                        : null;
            return LayoutBuilder(
                key: itemKey,
                builder: (context, constraints) {
                  final actions = Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                            tooltip: tr.text('decrease_qty'),
                            onPressed: () => _decreaseOrMarkCartItem(index),
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 19)),
                        SizedBox(
                            width: 54,
                            child: TextFormField(
                                key: ValueKey(
                                    'cart_quantity_${item.product.id}_${item.unitName}_${item.quantity}'),
                                initialValue: editedQuantity,
                                textAlign: TextAlign.center,
                                keyboardType: item.product.allowsDecimalQuantity
                                    ? const TextInputType.numberWithOptions(
                                        decimal: true)
                                    : TextInputType.number,
                                inputFormatters: item
                                        .product.allowsDecimalQuantity
                                    ? [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9.]'))
                                      ]
                                    : [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 5),
                                    border: OutlineInputBorder()),
                                onChanged: (value) => editedQuantity = value,
                                onFieldSubmitted: (value) =>
                                    _commitCartQuantityText(index, value),
                                onTapOutside: (_) => _commitCartQuantityText(
                                    index, editedQuantity))),
                        IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                            tooltip: tr.text('increase_qty'),
                            onPressed: () =>
                                _changeCartQuantity(index, item.quantity + 1),
                            icon:
                                const Icon(Icons.add_circle_outline, size: 19)),
                        IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                            tooltip: tr.text('delete'),
                            onPressed: () => _removeCartItem(index),
                            icon: const Icon(Icons.delete_outline, size: 19))
                      ]);
                  if (constraints.maxWidth < 520) {
                    return InkWell(
                        onTap: () => _selectCartIndex(index),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                            decoration: BoxDecoration(
                                color: rowColor,
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 6),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    if (item.needsAutoCorrection) ...[
                                      Icon(Icons.warning_amber_rounded,
                                          size: 18,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer),
                                      const SizedBox(width: 6)
                                    ],
                                    if (isPendingDelete) ...[
                                      Icon(Icons.delete_sweep_outlined,
                                          size: 18,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer),
                                      const SizedBox(width: 6)
                                    ],
                                    Expanded(
                                        child: Text(item.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall)),
                                    const SizedBox(width: 8),
                                    Text(_cartLineTotalText(item),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800))
                                  ]),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            '${item.product.code} • ${formatUsdReferenceAmount(item.unitPrice, widget.store.runtime.profile)} • ${_formatQuantity(item.quantity)} ${item.unitName} • ${_stockAvailabilityLabel(item.product, tr, includeUnit: true)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall)),
                                    actions
                                  ])
                                ])));
                  }
                  return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      minVerticalPadding: 2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      tileColor: rowColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      leading: item.needsAutoCorrection || isPendingDelete
                          ? Icon(
                              isPendingDelete
                                  ? Icons.delete_sweep_outlined
                                  : Icons.warning_amber_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)
                          : null,
                      title: Row(children: [
                        Expanded(
                            child: Text(item.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(_cartLineTotalText(item),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800))
                      ]),
                      subtitle: Text(
                          '${item.product.code} • ${formatUsdReferenceAmount(item.unitPrice, widget.store.runtime.profile)} • ${_formatQuantity(item.quantity)} ${item.unitName} • ${_stockAvailabilityLabel(item.product, tr, includeUnit: true)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => _selectCartIndex(index),
                      trailing: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: VentioResponsive.adaptiveWidth(context,
                                  mobile: 144, tablet: 164, desktop: 178)),
                          child: actions));
                });
          });
    }

    final Widget cartContent;
    if (_cart.isEmpty) {
      final emptyState = Center(child: Text(tr.text('invoice_empty')));
      cartContent = expandCartList
          ? Expanded(child: emptyState)
          : SizedBox(height: 140, child: emptyState);
    } else {
      final list = cartList(
          shrinkWrap: !expandCartList,
          physics:
              expandCartList ? null : const NeverScrollableScrollPhysics());
      cartContent = expandCartList ? Expanded(child: list) : list;
    }
    return Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35)),
        child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr.text('cart'),
                        style: Theme.of(context).textTheme.titleLarge),
                    Chip(
                        label: Text(
                            '${tr.text('items')}: ${_formatQuantity(_itemsCount)}')),
                    if (_cart.isNotEmpty)
                      TextButton.icon(
                          onPressed:
                              widget.store.security.canSell ? _confirmClearCart : null,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(tr.text('clear_cart'))),
                    if (_cart.isNotEmpty)
                      TextButton.icon(
                          onPressed:
                              widget.store.security.canSell ? _holdCurrentCart : null,
                          icon: const Icon(Icons.pause_circle_outline),
                          label: Text(tr.text('hold'))),
                    if (_heldCarts.isNotEmpty)
                      TextButton.icon(
                          onPressed: widget.store.security.canSell
                              ? _showHeldCartsDialog
                              : null,
                          icon: const Icon(
                              Icons.playlist_add_check_circle_outlined),
                          label: Text(
                              '${tr.text('restore')} (${_heldCarts.length})'))
                  ]),
              const SizedBox(height: 8),
              cartContent,
              if (showTotals) ...[
                const Divider(height: 24),
                _totalLine(
                    tr.text('subtotal'),
                    _formatSaleCurrency(
                        _currencyFromBase(_subtotal, _invoiceCurrency),
                        _invoiceCurrency)),
                _totalLine(
                    tr.text('discount'),
                    _formatSaleCurrency(
                        _currencyFromBase(_discount, _invoiceCurrency),
                        _invoiceCurrency)),
                if (_discount > _subtotal)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(tr.text('discount_exceeds_subtotal'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 8),
                _totalLine(tr.text('total'),
                    _formatSaleCurrency(_invoiceTotal, _invoiceCurrency),
                    isBold: true)
              ],
              if (showActions) ...[
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final primary = FilledButton.icon(
                      onPressed: _cart.isEmpty || !widget.store.security.canSell
                          ? null
                          : _openPaymentPage,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(tr.text('continue_payment')));
                  final secondary = OutlinedButton.icon(
                      onPressed: _cart.isEmpty || !widget.store.security.canSell
                          ? null
                          : _openPaymentPage,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(tr.text('continue_payment')));
                  if (constraints.maxWidth < 460) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          primary,
                          const SizedBox(height: 8),
                          secondary
                        ]);
                  }
                  return Row(children: [
                    Expanded(child: primary),
                    const SizedBox(width: 12),
                    Expanded(child: secondary)
                  ]);
                })
              ]
            ])));
  }
}
