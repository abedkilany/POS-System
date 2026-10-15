// ignore_for_file: invalid_use_of_protected_member
part of 'products_page.dart';

extension _ProductDialogStatePart3 on _ProductDialogState {
  Future<void> _loadSupplierOptions() async {
    final page = await LocalDatabaseService.querySuppliersFromSqlite(
      limit: 500,
    );
    if (!mounted || page == null) return;
    setState(() => _supplierOptions = page.items);
  }

  double? _costUsd() {
    final cost = double.tryParse(costController.text.trim());
    if (cost == null) return null;
    return toUsdReferencePrice(cost, costCurrency, widget.store.runtime.profile);
  }

  void _setControllerNumber(TextEditingController controller, double value) {
    final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
    if (controller.text != text) controller.text = text;
  }

  void _syncMarginFromPrice(
      TextEditingController price, TextEditingController margin) {
    final costUsd = _costUsd();
    final sale = double.tryParse(price.text.trim());
    if (costUsd == null || costUsd <= 0 || sale == null) return;
    final saleUsd =
        toUsdReferencePrice(sale, priceCurrency, widget.store.runtime.profile);
    _setControllerNumber(margin, (saleUsd / costUsd - 1) * 100);
  }

  void _syncPriceFromMargin(
      TextEditingController price, TextEditingController margin) {
    final costUsd = _costUsd();
    final marginValue = double.tryParse(margin.text.trim());
    if (costUsd == null || marginValue == null) return;
    final saleUsd = costUsd * (1 + marginValue / 100);
    _setControllerNumber(
      price,
      fromUsdReferencePrice(saleUsd, priceCurrency, widget.store.runtime.profile),
    );
  }

  void _syncAllMargins() {
    _syncMarginFromPrice(priceController, retailMarginController);
    _syncMarginFromPrice(wholesalePriceController, wholesaleMarginController);
    _syncMarginFromPrice(
        bulkWholesalePriceController, bulkWholesaleMarginController);
  }

  Future<void> _scanBarcodeWithCamera() async {
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
    setState(() => barcodeController.text = code.trim());
  }

  Future<void> _pickProductImage() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    final file = result?.files.single;
    if (file == null) return;
    setState(() => imagePath = file.path ?? file.name);
  }

  Future<void> _copyBarcode() async {
    final tr = AppLocalizations.of(context);
    final code = barcodeController.text.trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('barcode_copied'))));
  }

  void _generateBarcode() {
    final used = widget.store.catalog.products
        .where((item) => item.id != widget.product?.id)
        .map((item) => item.barcode.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    var seed = DateTime.now().microsecondsSinceEpoch % 1000000000000;
    String value;
    do {
      final body = seed.toString().padLeft(12, '0');
      var sum = 0;
      for (var index = 0; index < body.length; index++) {
        final digit = int.parse(body[index]);
        sum += digit * (index.isEven ? 1 : 3);
      }
      final checkDigit = (10 - (sum % 10)) % 10;
      value = '$body$checkDigit';
      seed = (seed + 1) % 1000000000000;
    } while (used.contains(value));
    setState(() => barcodeController.text = value);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final name = nameController.text.trim();
    final originalPrice = double.tryParse(priceController.text.trim()) ?? 0;
    final originalCost = double.tryParse(costController.text.trim()) ?? 0;
    final rate = widget.store.runtime.profile.usdToLbpRate;
    final usdPrice = toUsdReferencePrice(
        originalPrice, priceCurrency, widget.store.runtime.profile);
    final usdCost = toUsdReferencePrice(
        originalCost, costCurrency, widget.store.runtime.profile);
    Navigator.pop(
      context,
      _ProductFormResult(
        addToQuickProducts: addToQuickProducts,
        priceSave: () async {
          await _saveProductPriceDrafts(
              _productId, originalPrice, priceCurrency);
          final wholesale =
              double.tryParse(wholesalePriceController.text.trim());
          if (wholesale != null) {
            await widget.store.catalog.setProductBasePriceForList(
              productId: _productId,
              priceListId: 'wholesale',
              amount: wholesale,
              currencyCode: priceCurrency,
            );
          }
          final bulkWholesale =
              double.tryParse(bulkWholesalePriceController.text.trim());
          if (bulkWholesale != null) {
            await widget.store.catalog.setProductBasePriceForList(
              productId: _productId,
              priceListId: 'wholesale_bulk',
              amount: bulkWholesale,
              currencyCode: priceCurrency,
            );
          }
        },
        supplierPriceSave: () => _saveSupplierPriceDrafts(_productId),
        product: Product(
          id: _productId,
          name: name,
          nameEn: '',
          nameAr: '',
          code: _resolvedSku(),
          barcode: barcodeController.text.trim(),
          category: category.trim(),
          brand: brand.trim(),
          supplier: '',
          description: descriptionController.text.trim(),
          price: usdPrice,
          originalPrice: originalPrice,
          originalCurrency: priceCurrency,
          usdPrice: usdPrice,
          exchangeRateAtEntry: rate,
          cost: usdCost,
          originalCost: originalCost,
          costCurrency: costCurrency,
          usdCost: usdCost,
          costExchangeRateAtEntry: rate,
          stock: trackStock
              ? (double.tryParse(stockController.text.trim()) ?? 0)
              : 0,
          lowStockThreshold: trackStock
              ? (int.tryParse(lowStockController.text.trim()) ?? 5)
              : 0,
          unit: unit.trim(),
          quantityType: quantityType,
          saleUnits: saleUnitDrafts
              .map((item) => item.toSaleUnit(widget.store.runtime.profile))
              .where((item) =>
                  item.name.trim().isNotEmpty && item.conversionToBase > 0)
              .toList(),
          trackStock: trackStock,
          expiryTrackingEnabled: trackStock && expiryTrackingEnabled,
          expiryEntryRequired: true,
          expiryAlertDays:
              int.tryParse(expiryAlertDaysController.text.trim()) ?? 30,
          defaultShelfLifeDays:
              int.tryParse(defaultShelfLifeDaysController.text.trim()) ?? 0,
          minimumReceiptShelfLifeDays:
              int.tryParse(minimumReceiptShelfLifeDaysController.text.trim()) ??
                  0,
          isActive: isActive,
          createdAt: widget.product?.createdAt,
          updatedAt: widget.product?.updatedAt,
          deletedAt: widget.product?.deletedAt,
          deviceId: widget.product?.deviceId ?? '',
          syncStatus: widget.product?.syncStatus ?? 'pending',
          storeId: widget.product?.storeId ?? '',
          branchId: widget.product?.branchId ?? '',
          version: widget.product?.version ?? 1,
          lastModifiedByDeviceId: widget.product?.lastModifiedByDeviceId ?? '',
          imagePath: imagePath.trim(),
          taxProfileId: taxProfileId.trim(),
        ),
      ),
    );
  }

  Future<void> _saveProductPriceDrafts(
      String productId, double amount, String currencyCode) async {
    final previousBasePrice = widget.store.catalog.defaultProductPriceFor(productId);
    await widget.store.catalog.setDefaultProductBasePrice(
      productId: productId,
      unitId: 'base',
      amount: amount,
      currencyCode: currencyCode,
    );
    final basePrice = widget.store.catalog.defaultProductPriceFor(productId);
    if (basePrice != null) {
      final activeCurrencies = <String>{};
      for (final draft in priceOverrideDrafts) {
        final normalizedCurrency = draft.currencyCode.trim().toUpperCase();
        final overrideAmount = double.tryParse(draft.amountText.trim());
        if (normalizedCurrency.isEmpty ||
            normalizedCurrency == currencyCode.trim().toUpperCase() ||
            overrideAmount == null ||
            overrideAmount < 0) {
          continue;
        }
        activeCurrencies.add(normalizedCurrency);
        await widget.store.catalog.setProductPriceOverride(
          productPriceId: basePrice.id,
          currencyCode: normalizedCurrency,
          amount: overrideAmount,
        );
      }
      final existingOverridePriceIds = <String>{basePrice.id};
      if (previousBasePrice != null) {
        existingOverridePriceIds.add(previousBasePrice.id);
      }
      for (final item in widget.store.catalog.productPriceOverrides) {
        if (existingOverridePriceIds.contains(item.productPriceId) &&
            item.isActive &&
            !activeCurrencies.contains(item.currencyCode)) {
          await widget.store.catalog.removeProductPriceOverride(
              item.productPriceId, item.currencyCode);
        }
      }
    }
    for (final draft in saleUnitDrafts) {
      final unit = draft.toSaleUnit(widget.store.runtime.profile);
      if (unit.id.trim().isEmpty ||
          unit.name.trim().isEmpty ||
          unit.conversionToBase <= 0) {
        continue;
      }
      await widget.store.catalog.setDefaultProductBasePrice(
        productId: productId,
        unitId: unit.id,
        amount: unit.originalPrice,
        currencyCode: unit.originalCurrency,
      );
    }
  }

  Future<void> _saveSupplierPriceDrafts(String productId) async {
    final activeDraftIds = supplierPriceDrafts.map((item) => item.id).toSet();
    final existing = widget.store.commerce.supplierProductPricesForProduct(productId);
    for (final item in supplierPriceDrafts) {
      await widget.store
          .commerce.addOrUpdateSupplierProductPrice(item.copyWith(productId: productId));
    }
    for (final item in existing) {
      if (!activeDraftIds.contains(item.id)) {
        await widget.store.commerce.deleteSupplierProductPrice(item.id);
      }
    }
  }

  Future<void> _addCatalogItem(BuildContext context, String type) async {
    final item = await showDialog<CatalogItem>(
        context: context, builder: (_) => _CatalogItemDialog(type: type));
    if (item == null) return;
    if (type == 'category') {
      await widget.store.catalog.addOrUpdateCategory(item);
      setState(() => category = item.nameEn.trim().isNotEmpty
          ? item.nameEn.trim()
          : item.nameAr.trim());
    } else if (type == 'brand') {
      await widget.store.catalog.addOrUpdateBrand(item);
      setState(() => brand = item.nameEn.trim().isNotEmpty
          ? item.nameEn.trim()
          : item.nameAr.trim());
    } else {
      await widget.store.catalog.addOrUpdateUnit(item);
      setState(() => unit =
          item.code.trim().isNotEmpty ? item.code.trim() : item.nameEn.trim());
    }
  }

  Future<void> _manageCatalogItems(BuildContext context, String type) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogManagerDialog(store: widget.store, type: type),
    );
    setState(() {});
  }

  String _resolvedSku() => codeController.text.trim().isEmpty
      ? _generateUniqueSku()
      : codeController.text.trim();

  String _generateUniqueSku() {
    final used = widget.store.catalog.products
        .where((item) => item.id != widget.product?.id)
        .map((item) => item.code.trim().toUpperCase())
        .toSet();
    var counter = widget.store.catalog.products.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }

  String? _uniqueSku(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final exists = widget.store.catalog.products.any((item) =>
        item.id != widget.product?.id &&
        item.code.trim().toLowerCase() == normalized);
    return exists
        ? AppLocalizations.of(context).text('sku_already_exists')
        : null;
  }

  String? _nameRequired() {
    if (nameController.text.trim().isNotEmpty) {
      return null;
    }
    return AppLocalizations.of(context).text('required');
  }

  String? _requiredValue(String? value) {
    return (value ?? '').trim().isEmpty
        ? AppLocalizations.of(context).text('required')
        : null;
  }

  String? _nonNegativeNumber(String? value) {
    final number = double.tryParse((value ?? '').trim());
    return number == null || number < 0
        ? AppLocalizations.of(context).text('invalid_number')
        : null;
  }

  String? _optionalNonNegativeNumber(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return _nonNegativeNumber(value);
  }

  String? _nonNegativeInteger(String? value) {
    final number = int.tryParse((value ?? '').trim());
    return number == null || number < 0
        ? AppLocalizations.of(context).text('invalid_number')
        : null;
  }
}
