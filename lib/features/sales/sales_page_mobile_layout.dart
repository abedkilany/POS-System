part of 'sales_page.dart';

extension _SalesPageMobileLayout on _SalesPageState {
  Widget _buildMobileSalesLayout(BuildContext context, AppLocalizations tr,
      List<Product> products, double pagePadding) {
    return SafeArea(
        child: Column(children: [
      Expanded(
          child: SingleChildScrollView(
              padding: EdgeInsets.all(pagePadding),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    _buildMobileSaleControls(context, tr, products),
                    const SizedBox(height: 8),
                    _buildCart(context, tr,
                        compactActions: true,
                        showTotals: false,
                        showActions: false,
                        expandCartList: false)
                  ]))),
      Padding(
          padding:
              EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, pagePadding),
          child: _buildMobileInvoiceSummary(context, tr))
    ]));
  }

  Widget _buildMobileSaleControls(
      BuildContext context, AppLocalizations tr, List<Product> products) {
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: VentioResponsive.cardInsets(context),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSalePriceTypeSelector(context, tr),
                  const SizedBox(height: 10),
                  _buildBarcodeStation(context, tr,
                      products: products, embedded: true),
                  if (_scannerActive) ...[
                    const SizedBox(height: 10),
                    _buildEmbeddedScannerPreview()
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      runAlignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSaleShiftMobileAction(tr),
                        if (true)
                          _MobileSaleAction(
                              icon: Icons.search,
                              label: tr.text('search'),
                              onTap: () => _showProductSearchSheet(products)),
                        _MobileSaleAction(
                            icon: Icons.grid_view_rounded,
                            label: tr.text('quick_products'),
                            onTap: () => _showQuickProductsSheet(products)),
                        if (_legacyShiftButtonVisible)
                          _MobileSaleAction(
                              icon: Icons.point_of_sale_outlined,
                              label: 'الوردية',
                              onTap: () {}),
                        _MobileSaleAction(
                            icon: Icons.receipt_long_outlined,
                            label: tr.text('recent_invoices'),
                            onTap: _showInvoicesSheet),
                        if (widget.store
                            .security.hasPermission(AppPermission.salesCancel))
                          _MobileSaleAction(
                              icon: Icons.assignment_return_outlined,
                              label: tr.text('new_sales_return'),
                              onTap: () => _openSaleReturnDialog(context))
                      ])
                ])));
  }

  Widget _buildMobileInvoiceSummary(BuildContext context, AppLocalizations tr) {
    return _buildSaleTotalBar(context, tr, compact: true);
  }

  Widget _buildSaleTotalBar(BuildContext context, AppLocalizations tr,
      {bool compact = false}) {
    final totalText =
        formatUsdReferenceAmount(_total, widget.store.runtime.profile);
    final hasDiscount = _discount > 0;
    final content = compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      '${_formatQuantity(_itemsCount)} ${tr.text('items_count')}',
                      style: Theme.of(context).textTheme.bodyMedium)),
              Text(totalText,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900))
            ]),
            if (hasDiscount) ...[
              const SizedBox(height: 4),
              Text(
                  '${tr.text('discount')}: ${formatUsdReferenceAmount(_discount, widget.store.runtime.profile)}',
                  style: Theme.of(context).textTheme.bodySmall)
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
                key: const ValueKey('SalesContinuePaymentMobile'),
                onPressed: _cart.isEmpty ? null : _openPaymentPage,
                icon: const Icon(Icons.payments_outlined),
                label: Text(tr.text('continue_payment')))
          ])
        : Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr.text('total'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(totalText,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  if (hasDiscount)
                    Text(
                        '${tr.text('discount')}: ${formatUsdReferenceAmount(_discount, widget.store.runtime.profile)}',
                        style: Theme.of(context).textTheme.bodySmall)
                ])),
            FilledButton.icon(
                key: const ValueKey('SalesContinuePaymentDesktop'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    visualDensity: VisualDensity.compact),
                onPressed: _cart.isEmpty ? null : _openPaymentPage,
                icon: const Icon(Icons.payments_outlined),
                label: Text(tr.text('continue_payment')))
          ]);
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 12, vertical: compact ? 12 : 4),
            child: content));
  }
}
