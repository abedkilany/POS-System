part of 'products_page.dart';

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController barcodeController;
  late final TextEditingController codeController;
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  late final TextEditingController wholesalePriceController;
  late final TextEditingController bulkWholesalePriceController;
  late final TextEditingController retailMarginController;
  late final TextEditingController wholesaleMarginController;
  late final TextEditingController bulkWholesaleMarginController;
  late final TextEditingController costController;
  late final TextEditingController stockController;
  late final TextEditingController lowStockController;
  late final TextEditingController expiryAlertDaysController;
  late final TextEditingController defaultShelfLifeDaysController;
  late final TextEditingController minimumReceiptShelfLifeDaysController;
  String category = '';
  String priceCurrency = 'USD';
  String costCurrency = 'USD';
  String taxProfileId = '';
  String brand = '';
  String unit = '';
  ProductQuantityType quantityType = ProductQuantityType.countable;
  late List<_SaleUnitDraft> saleUnitDrafts;
  bool trackStock = true;
  bool expiryTrackingEnabled = false;
  bool isActive = true;
  bool addToQuickProducts = false;
  String imagePath = '';
  late final String _productId;
  late List<SupplierProductPrice> supplierPriceDrafts;
  late List<_CurrencyPriceOverrideDraft> priceOverrideDrafts;
  List<Supplier> _supplierOptions = const <Supplier>[];
  Future<ProductCostSnapshot>? _costSnapshotFuture;

  @override
  void initState() {
    super.initState();
    final tr = AppLocalizations.of(context);
    final product = widget.product;
    if (product != null && product.trackStock) {
      _costSnapshotFuture = widget.store.productCostSnapshotForProduct(product);
    }
    _productId =
        product?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    supplierPriceDrafts = product == null
        ? <SupplierProductPrice>[]
        : widget.store.supplierProductPricesForProduct(product.id).toList();
    _supplierOptions = widget.store.suppliers.toList(growable: false);
    unawaited(_loadSupplierOptions());
    barcodeController = TextEditingController(text: product?.barcode ?? '');
    codeController =
        TextEditingController(text: product?.code ?? _generateUniqueSku());
    nameController = TextEditingController(
      text: product?.name.isNotEmpty == true
          ? product!.name
          : product?.nameEn.isNotEmpty == true
              ? product!.nameEn
              : product?.nameAr ?? '',
    );
    descriptionController =
        TextEditingController(text: product?.description ?? '');
    final defaultProductPrice = product == null
        ? null
        : widget.store.defaultProductPriceFor(product.id);
    priceOverrideDrafts = defaultProductPrice == null
        ? <_CurrencyPriceOverrideDraft>[]
        : widget.store.productPriceOverrides
            .where((item) =>
                item.productPriceId == defaultProductPrice.id && item.isActive)
            .map(_CurrencyPriceOverrideDraft.fromOverride)
            .toList();
    priceCurrency = defaultProductPrice?.baseCurrencyCode ??
        product?.originalCurrency ??
        widget.store.storeProfile.defaultProductCurrency;
    costCurrency = product?.costCurrency ??
        widget.store.storeProfile.defaultProductCurrency;
    final activeTaxProfiles = widget.store.storeProfile.activeTaxProfiles;
    final requestedTaxProfileId = product?.taxProfileId.trim() ?? '';
    if (activeTaxProfiles.any((item) => item.id == requestedTaxProfileId)) {
      taxProfileId = requestedTaxProfileId;
    } else if (activeTaxProfiles.any(
      (item) => item.id == widget.store.storeProfile.defaultTaxProfileId,
    )) {
      taxProfileId = widget.store.storeProfile.defaultTaxProfileId;
    } else {
      taxProfileId =
          activeTaxProfiles.isEmpty ? '' : activeTaxProfiles.first.id;
    }
    priceController = TextEditingController(
        text: defaultProductPrice?.baseAmount.toString() ??
            product?.originalPrice.toString() ??
            '');
    wholesalePriceController = TextEditingController(
        text: product == null
            ? ''
            : widget.store
                    .productPriceFor(product.id, 'wholesale')
                    ?.baseAmount
                    .toString() ??
                '');
    bulkWholesalePriceController = TextEditingController(
        text: product == null
            ? ''
            : widget.store
                    .productPriceFor(product.id, 'wholesale_bulk')
                    ?.baseAmount
                    .toString() ??
                '');
    costController =
        TextEditingController(text: product?.originalCost.toString() ?? '');
    retailMarginController = TextEditingController();
    wholesaleMarginController = TextEditingController();
    bulkWholesaleMarginController = TextEditingController();
    _syncAllMargins();
    stockController =
        TextEditingController(text: product?.stock.toString() ?? '');
    lowStockController = TextEditingController(
        text: (product?.lowStockThreshold ?? 5).toString());
    expiryAlertDaysController = TextEditingController(
        text: (product?.expiryAlertDays ?? 30).toString());
    defaultShelfLifeDaysController = TextEditingController(
        text: (product?.defaultShelfLifeDays ?? 0).toString());
    minimumReceiptShelfLifeDaysController = TextEditingController(
        text: (product?.minimumReceiptShelfLifeDays ?? 0).toString());
    imagePath = product?.imagePath ?? '';
    category = product?.category ??
        (widget.store.categories.isNotEmpty
            ? widget.store.categories.first.code.isNotEmpty
                ? widget.store.categories.first.code
                : widget.store.categories.first.nameEn
            : tr.text('general'));
    brand = product?.brand ?? '';
    unit = product?.unit ?? '';
    quantityType = product?.quantityType ?? ProductQuantityType.countable;
    saleUnitDrafts = (product?.saleUnits ?? const [])
        .map(_SaleUnitDraft.fromSaleUnit)
        .toList();
    trackStock = product?.trackStock ?? true;
    expiryTrackingEnabled = product?.expiryTrackingEnabled ?? false;
    isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    barcodeController.dispose();
    codeController.dispose();
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    wholesalePriceController.dispose();
    bulkWholesalePriceController.dispose();
    retailMarginController.dispose();
    wholesaleMarginController.dispose();
    bulkWholesaleMarginController.dispose();
    costController.dispose();
    stockController.dispose();
    lowStockController.dispose();
    expiryAlertDaysController.dispose();
    defaultShelfLifeDaysController.dispose();
    minimumReceiptShelfLifeDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final width =
        math.min(MediaQuery.sizeOf(context).width - 32, 760).toDouble();
    return AlertDialog(
      title: Text(widget.product == null
          ? tr.text('add_product')
          : tr.text('edit_product')),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProductFormSection(
                  icon: Icons.inventory_2_outlined,
                  title: tr.text('basic_information'),
                  children: [
                    _ProductImagePicker(
                      imagePath: imagePath,
                      onPick: _pickProductImage,
                      onClear: imagePath.trim().isEmpty
                          ? null
                          : () => setState(() => imagePath = ''),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFields(children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: barcodeController,
                            decoration: InputDecoration(
                              labelText: tr.text('barcode'),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: tr.text('copy_barcode'),
                                    onPressed: _copyBarcode,
                                    icon: const Icon(Icons.copy_outlined),
                                  ),
                                  IconButton(
                                    tooltip: tr.text('scan_with_camera'),
                                    onPressed: _scanBarcodeWithCamera,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                  ),
                                ],
                              ),
                            ),
                            validator: _requiredValue,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              onPressed: _generateBarcode,
                              icon: const Icon(Icons.qr_code_2_outlined),
                              label: Text(tr.text('generate_barcode')),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: '${tr.text('product_name')} *',
                        ),
                        validator: (_) => _nameRequired(),
                      ),
                      _CatalogDropdown(
                        label: tr.text('category'),
                        value: category,
                        items: widget.store.categories,
                        onChanged: (value) => setState(() => category = value),
                        onAdd: () => _addCatalogItem(context, 'category'),
                        onManage: () =>
                            _manageCatalogItems(context, 'category'),
                      ),
                      _CatalogDropdown(
                        label: tr.text('brand'),
                        value: brand,
                        items: widget.store.brands,
                        onChanged: (value) => setState(() => brand = value),
                        onAdd: () => _addCatalogItem(context, 'brand'),
                        onManage: () => _manageCatalogItems(context, 'brand'),
                      ),
                      _CatalogDropdown(
                        label: '${tr.text('unit')} *',
                        value: unit,
                        items: widget.store.units,
                        onChanged: (value) => setState(() => unit = value),
                        onAdd: () => _addCatalogItem(context, 'unit'),
                        onManage: () => _manageCatalogItems(context, 'unit'),
                        validator: _requiredValue,
                      ),
                      DropdownButtonFormField<ProductQuantityType>(
                        initialValue: quantityType,
                        decoration: InputDecoration(
                            labelText: tr.text('quantity_type')),
                        items: [
                          DropdownMenuItem(
                              value: ProductQuantityType.countable,
                              child: Text(tr.text('quantity_type_countable'))),
                          DropdownMenuItem(
                              value: ProductQuantityType.measurable,
                              child: Text(tr.text('quantity_type_measurable'))),
                        ],
                        onChanged: (value) => setState(() => quantityType =
                            value ?? ProductQuantityType.countable),
                      ),
                    ]),
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.text('expiry_tracking')),
                      subtitle: Text(tr.text('expiry_tracking_help')),
                      value: trackStock && expiryTrackingEnabled,
                      onChanged: trackStock
                          ? (value) =>
                              setState(() => expiryTrackingEnabled = value)
                          : null,
                    ),
                    if (trackStock && expiryTrackingEnabled) ...[
                      _ResponsiveFields(children: [
                        TextFormField(
                          controller: expiryAlertDaysController,
                          decoration: InputDecoration(
                              labelText: tr.text('expiry_alert_days')),
                          keyboardType: TextInputType.number,
                          validator: _nonNegativeInteger,
                        ),
                        TextFormField(
                          controller: defaultShelfLifeDaysController,
                          decoration: InputDecoration(
                              labelText: tr.text('default_shelf_life_days')),
                          keyboardType: TextInputType.number,
                          validator: _nonNegativeInteger,
                        ),
                        TextFormField(
                          controller: minimumReceiptShelfLifeDaysController,
                          decoration: InputDecoration(
                              labelText:
                                  tr.text('minimum_receipt_shelf_life_days')),
                          keyboardType: TextInputType.number,
                          validator: _nonNegativeInteger,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(tr.text('advanced_sku')),
                      subtitle: Text(
                          '${tr.text('auto_generated')}: ${codeController.text}'),
                      children: [
                        TextFormField(
                            controller: codeController,
                            decoration:
                                InputDecoration(labelText: tr.text('sku_code')),
                            validator: _uniqueSku),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: descriptionController,
                        decoration:
                            InputDecoration(labelText: tr.text('description')),
                        minLines: 2,
                        maxLines: 3),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.payments_outlined,
                  title: tr.text('pricing'),
                  children: [
                    if (_costSnapshotFuture != null) ...[
                      FutureBuilder<ProductCostSnapshot>(
                        future: _costSnapshotFuture,
                        builder: (context, snapshot) {
                          final value = snapshot.data;
                          if (value == null) {
                            return const LinearProgressIndicator(minHeight: 2);
                          }
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                Text(
                                  value.hasInventory
                                      ? '${tr.text('current_inventory_cost')}: ${formatUsdReferenceAmount(value.currentInventoryUnitCost, widget.store.storeProfile)} (${value.batchCount} ${tr.text('batches_label')})'
                                      : '${tr.text('current_inventory_cost')}: —',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${tr.text('last_purchase_cost_label')}: ${value.lastPurchaseUnitCost == null ? '—' : formatUsdReferenceAmount(value.lastPurchaseUnitCost!, widget.store.storeProfile)}',
                                ),
                                Text(
                                  '${tr.text('reference_cost')}: ${formatUsdReferenceAmount(value.referenceUnitCost, widget.store.storeProfile)}',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    _ResponsiveFields(children: [
                      _MoneyField(
                          controller: priceController,
                          currency: priceCurrency,
                          label: tr.text('retail_price'),
                          currencyLabel: tr.text('price_currency'),
                          validator: _nonNegativeNumber,
                          onChanged: (_) => setState(() => _syncMarginFromPrice(
                              priceController, retailMarginController)),
                          onCurrencyChanged: (value) =>
                              setState(() => priceCurrency = value)),
                      _MoneyField(
                          controller: costController,
                          currency: costCurrency,
                          label: tr.text('reference_cost'),
                          currencyLabel: tr.text('cost_currency'),
                          validator: _nonNegativeNumber,
                          onChanged: (_) => setState(_syncAllMargins),
                          onCurrencyChanged: (value) => setState(() {
                                costCurrency = value;
                                _syncAllMargins();
                              })),
                    ]),
                    const SizedBox(height: 12),
                    _ResponsiveFields(children: [
                      _MoneyField(
                          controller: wholesalePriceController,
                          currency: priceCurrency,
                          label: tr.text('wholesale_price'),
                          currencyLabel: tr.text('price_currency'),
                          validator: _optionalNonNegativeNumber,
                          onChanged: (_) => setState(() => _syncMarginFromPrice(
                              wholesalePriceController,
                              wholesaleMarginController)),
                          onCurrencyChanged: (value) =>
                              setState(() => priceCurrency = value)),
                      _MoneyField(
                          controller: bulkWholesalePriceController,
                          currency: priceCurrency,
                          label: tr.text('bulk_wholesale_price'),
                          currencyLabel: tr.text('price_currency'),
                          validator: _optionalNonNegativeNumber,
                          onChanged: (_) => setState(() => _syncMarginFromPrice(
                              bulkWholesalePriceController,
                              bulkWholesaleMarginController)),
                          onCurrencyChanged: (value) =>
                              setState(() => priceCurrency = value)),
                    ]),
                    const SizedBox(height: 12),
                    _ResponsiveFields(children: [
                      _MarginField(
                        controller: retailMarginController,
                        label: tr.text('retail_margin'),
                        onChanged: (_) => setState(() => _syncPriceFromMargin(
                            priceController, retailMarginController)),
                      ),
                      _MarginField(
                        controller: wholesaleMarginController,
                        label: tr.text('wholesale_margin'),
                        onChanged: (_) => setState(() => _syncPriceFromMargin(
                            wholesalePriceController,
                            wholesaleMarginController)),
                      ),
                      _MarginField(
                        controller: bulkWholesaleMarginController,
                        label: tr.text('bulk_wholesale_margin'),
                        onChanged: (_) => setState(() => _syncPriceFromMargin(
                            bulkWholesalePriceController,
                            bulkWholesaleMarginController)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: widget.store.storeProfile.activeTaxProfiles
                              .any((item) => item.id == taxProfileId)
                          ? taxProfileId
                          : (widget.store.storeProfile.activeTaxProfiles.isEmpty
                              ? null
                              : widget.store.storeProfile.activeTaxProfiles
                                  .first.id),
                      decoration: InputDecoration(
                        labelText: tr.text('tax_profile'),
                        helperText: tr.text('tax_profile_product_desc'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final profile
                            in widget.store.storeProfile.activeTaxProfiles)
                          DropdownMenuItem<String>(
                            value: profile.id,
                            child: Text(
                              '${profile.name} (${profile.code}${profile.treatment.name == 'standard' ? ' ${profile.ratePercent.toStringAsFixed(profile.ratePercent == profile.ratePercent.roundToDouble() ? 0 : 2)}%' : ''})',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => taxProfileId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _CurrencyPriceOverridesEditor(
                      drafts: priceOverrideDrafts,
                      baseCurrencyCode: priceCurrency,
                      availableCurrencyCodes: widget
                          .store.storeProfile.currencies
                          .map((item) => item.code)
                          .toList(growable: false),
                      onChanged: (items) =>
                          setState(() => priceOverrideDrafts = items),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.local_shipping_outlined,
                  title: tr.text('supplier_prices'),
                  children: [
                    _SupplierPricesEditor(
                      prices: supplierPriceDrafts,
                      productId: _productId,
                      suppliers: _supplierOptions,
                      storeProfile: widget.store.storeProfile,
                      onChanged: (items) =>
                          setState(() => supplierPriceDrafts = items),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.warehouse_outlined,
                  title: tr.text('inventory_stock'),
                  children: [
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr.text('track_quantity')),
                        subtitle: Text(tr.text('track_quantity_help')),
                        value: trackStock,
                        onChanged: (value) =>
                            setState(() => trackStock = value)),
                    _ResponsiveFields(children: [
                      TextFormField(
                          enabled: trackStock && widget.product == null,
                          controller: stockController,
                          decoration: InputDecoration(
                              labelText: tr.text('opening_stock'),
                              helperText: !trackStock
                                  ? tr.text('stock_ignored_non_stock')
                                  : widget.product == null
                                      ? null
                                      : tr.text('adjust_stock')),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: trackStock
                              ? (quantityType == ProductQuantityType.measurable
                                  ? _nonNegativeNumber
                                  : _nonNegativeInteger)
                              : null),
                      TextFormField(
                          enabled: trackStock,
                          controller: lowStockController,
                          decoration: InputDecoration(
                              labelText: tr.text('low_stock_alert'),
                              helperText: trackStock
                                  ? null
                                  : tr.text('no_low_stock_alerts_non_stock')),
                          keyboardType: TextInputType.number,
                          validator: trackStock ? _nonNegativeInteger : null),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.view_module_outlined,
                  title: tr.text('sale_units'),
                  children: [
                    _SaleUnitsEditor(
                      saleUnits: saleUnitDrafts,
                      storeProfile: widget.store.storeProfile,
                      existingBarcodes: widget.store.products
                          .where((item) => item.id != widget.product?.id)
                          .expand((item) => <String>[
                                item.barcode,
                                ...item.saleUnits.map((unit) => unit.barcode),
                              ])
                          .toSet(),
                      onChanged: (items) =>
                          setState(() => saleUnitDrafts = items),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('add_to_quick_products')),
                    subtitle: Text(tr.text('add_to_quick_products_help')),
                    value: addToQuickProducts,
                    onChanged: (value) =>
                        setState(() => addToQuickProducts = value)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('active_product')),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('cancel'))),
        FilledButton(onPressed: _save, child: Text(tr.text('save'))),
      ],
    );
  }
}

class _CurrencyPriceOverrideDraft {
  const _CurrencyPriceOverrideDraft({
    required this.currencyCode,
    required this.amountText,
  });

  final String currencyCode;
  final String amountText;

  factory _CurrencyPriceOverrideDraft.fromOverride(
      ProductPriceOverride override) {
    return _CurrencyPriceOverrideDraft(
      currencyCode: override.currencyCode,
      amountText: override.amount.toString(),
    );
  }

  _CurrencyPriceOverrideDraft copyWith(
      {String? currencyCode, String? amountText}) {
    return _CurrencyPriceOverrideDraft(
      currencyCode: currencyCode ?? this.currencyCode,
      amountText: amountText ?? this.amountText,
    );
  }
}
