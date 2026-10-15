// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageProductData on _SalesPageState {
  bool get _legacyShiftButtonVisible => false;

  void _handleStoreChanged() {
    if (!mounted) return;
    final nextRevision = _currentStoreUiRevision();
    if (nextRevision == _storeUiRevision) return;
    setState(() {
      _storeUiRevision = nextRevision;
    });
  }

  int _currentStoreUiRevision() {
    return Object.hashAll(<Object?>[
      widget.store.salesPageRevision,
      widget.store.canViewSales,
      widget.store.canSell,
      widget.store.canManageDeliveryNotes,
      widget.store.canDeleteOrCancel,
      widget.store.hasPermission(AppPermission.salesPrint),
      widget.store.hasPermission(AppPermission.salesEdit),
      widget.store.hasPermission(AppPermission.salesExport),
      widget.store.saleWarehouseId
    ]);
  }

  Future<void> _refreshProductData(AppLocalizations tr) async {
    if (_refreshingProductData) return;
    setState(() => _refreshingProductData = true);
    try {
      await widget.store.refreshSalesProductData();
      if (!mounted) return;
      _visibleProductsCache.invalidate();
      _activeProductsCache.invalidate();
      _productSearchIndexCache.invalidate();
      _barcodeLookupCache.invalidate();
      _resetProductSearchReveal();
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.text('refresh_completed'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizeRuntimeMessage(error.toString(), tr))));
    } finally {
      if (mounted) setState(() => _refreshingProductData = false);
    }
  }

  double get _discount {
    final value = double.tryParse(_discountController.text) ?? 0;
    final normalized = value < 0 ? 0 : value;
    return toUsdReferencePrice(
        normalized.toDouble(), _discountCurrency, widget.store.storeProfile);
  }

  double get _discountGrossAmount =>
      _currencyFromBase(_subtotal, _discountCurrency);

  void _syncDiscountPercentFromAmount() {
    final gross = _discountGrossAmount;
    final amount = double.tryParse(_discountController.text.trim());
    if (gross <= 0 || amount == null) return;
    final percent = (amount.clamp(0, gross) / gross) * 100;
    final text = percent.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
    if (_discountPercentController.text != text) {
      _discountPercentController.text = text;
    }
  }

  void _syncDiscountAmountFromPercent() {
    final gross = _discountGrossAmount;
    final percent = double.tryParse(_discountPercentController.text.trim());
    if (gross <= 0 || percent == null) return;
    final amount = gross * (percent.clamp(0, 100) / 100);
    final text = amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
    if (_discountController.text != text) _discountController.text = text;
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);

  double get _invoiceProfitPercent {
    final revenueAfterDiscount =
        (_subtotal - _discount).clamp(0, double.infinity).toDouble();
    if (revenueAfterDiscount <= 0) return 0;
    return (_invoiceProfitAmount / revenueAfterDiscount) * 100;
  }

  double get _invoiceProfitAmount {
    final fallbackCost = _cart.fold<double>(
        0, (sum, item) => sum + item.baseQuantity * item.product.usdCost);
    final cost = _invoicePreviewBatchCostTotal ?? fallbackCost;
    final revenueAfterDiscount =
        (_subtotal - _discount).clamp(0, double.infinity).toDouble();
    return revenueAfterDiscount - cost;
  }

  Future<void> _refreshInvoiceBatchCostPreview() async {
    var totalCost = 0.0;
    for (final item in _cart) {
      var unitCost = item.product.usdCost;
      if (item.product.trackStock && item.baseQuantity > 0.000001) {
        try {
          unitCost = await widget.store.estimatedUnifiedBatchUnitCostForProduct(
              item.product,
              warehouseId: _selectedWarehouseId,
              requiredQuantity: item.baseQuantity);
        } catch (_) {}
      }
      totalCost += item.baseQuantity * unitCost;
    }
    _invoicePreviewBatchCostTotal = totalCost;
  }

  String _stockAvailabilityLabel(Product product, AppLocalizations tr,
      {bool includeUnit = false, String? warehouseId}) {
    if (!product.trackStock) return 'Non-stock';
    final available = widget.store
        .stockForWarehouse(product.id, warehouseId ?? _selectedWarehouseId);
    final quantity =
        includeUnit ? _formatQuantity(available) : available.toString();
    return includeUnit
        ? '${tr.text('stock')}: $quantity ${product.unit}'
        : '${tr.text('stock')}: $quantity';
  }

  double get _total =>
      (_subtotal - _discount).clamp(0, double.infinity).toDouble();

  double get _itemsCount =>
      _cart.fold<double>(0, (sum, item) => sum + item.quantity);

  bool get _isWalkInCustomer =>
      widget.store.sanitizeSelectedCustomerId(_selectedCustomerId) ==
      AppStore.walkInCustomerId;

  bool get _isCashPayment => _paymentMethod == 'Cash';

  bool get _isCreditPayment => _paymentMethod == 'Credit';

  bool get _showsCashReceived => !_isCashPayment;

  double get _saleExchangeRate {
    final manual = double.tryParse(_paymentExchangeRateController.text.trim());
    if (manual != null && manual > 0) return manual;
    return exchangeRate(
        _paymentCurrency, _invoiceCurrency, widget.store.storeProfile,
        effectiveAt: DateTime.now());
  }

  double get _rawInvoiceTotal => _currencyFromBase(_total, _invoiceCurrency);

  double get _invoiceTotal {
    final rawTotal = _rawInvoiceTotal;
    if (!_isCashPayment) return rawTotal;
    final amountInPaymentCurrency =
        _convertCurrencyAmount(rawTotal, _invoiceCurrency, _paymentCurrency);
    final roundedPaymentAmount = normalizeCashAmount(
        amountInPaymentCurrency, _paymentCurrency, widget.store.storeProfile);
    return _convertCurrencyAmount(
        roundedPaymentAmount, _paymentCurrency, _invoiceCurrency);
  }

  double get _cashRoundingDifferenceInInvoiceCurrency =>
      (_invoiceTotal - _rawInvoiceTotal);

  double get _cashReceivedInPaymentCurrency =>
      (double.tryParse(_paidAmountController.text.trim()) ?? 0)
          .clamp(0, double.infinity)
          .toDouble();

  double get _cashReceivedAmount => _convertCurrencyAmount(
          _cashReceivedInPaymentCurrency, _paymentCurrency, _invoiceCurrency)
      .clamp(0, _invoiceTotal)
      .toDouble();

  String get _derivedPaymentStatus {
    if (_isCreditPayment) return _cashReceivedAmount > 0 ? 'partial' : 'credit';
    return 'paid';
  }

  double get _derivedPaidAmount =>
      _isCreditPayment ? _cashReceivedAmount : _invoiceTotal;

  double _currencyFromBase(double amount, String currency) => convertCurrency(
      amount,
      widget.store.storeProfile.baseCurrency,
      currency,
      widget.store.storeProfile,
      effectiveAt: DateTime.now());

  double _convertCurrencyAmount(
      double amount, String fromCurrency, String toCurrency) {
    return convertCurrency(
        amount, fromCurrency, toCurrency, widget.store.storeProfile,
        effectiveAt: DateTime.now());
  }

  String _formatSaleCurrency(double amount, String currency) =>
      formatCurrency(amount, currency: currency);

  Map<String, String> _productSearchIndex() {
    return _productSearchIndexCache.getOrCompute(
        widget.store.productsRevision, 'product_search_index', () {
      final index = <String, String>{};
      for (final product in widget.store.products) {
        final buffer = StringBuffer()
          ..write(product.name)
          ..write(' ')
          ..write(product.nameEn)
          ..write(' ')
          ..write(product.nameAr)
          ..write(' ')
          ..write(product.code)
          ..write(' ')
          ..write(product.barcode)
          ..write(' ')
          ..write(product.category)
          ..write(' ')
          ..write(product.brand)
          ..write(' ')
          ..write(product.supplier)
          ..write(' ')
          ..write(product.unit);
        for (final unit in product.effectiveSaleUnits) {
          buffer
            ..write(' ')
            ..write(unit.name)
            ..write(' ')
            ..write(unit.barcode);
        }
        for (final unit in product.effectivePurchaseUnits) {
          buffer
            ..write(' ')
            ..write(unit.name)
            ..write(' ')
            ..write(unit.barcode);
        }
        index[product.id] = buffer.toString().toLowerCase();
      }
      return index;
    });
  }

  Map<String, _BarcodeProductMatch> _barcodeLookup() {
    return _barcodeLookupCache.getOrCompute(widget.store.productsRevision, () {
      final lookup = <String, _BarcodeProductMatch>{};
      for (final product in widget.store.products) {
        if (!product.isActive || product.isDeleted) continue;
        final saleUnits = product.effectiveSaleUnits;
        final defaultUnit = saleUnits.first;
        final code = product.code.trim().toLowerCase();
        if (code.isNotEmpty) {
          lookup[code] =
              _BarcodeProductMatch(product: product, unit: defaultUnit);
        }
        final barcode = product.barcode.trim().toLowerCase();
        if (barcode.isNotEmpty) {
          lookup[barcode] =
              _BarcodeProductMatch(product: product, unit: defaultUnit);
        }
        for (final unit in saleUnits) {
          final unitBarcode = unit.barcode.trim().toLowerCase();
          if (unitBarcode.isEmpty) continue;
          lookup[unitBarcode] =
              _BarcodeProductMatch(product: product, unit: unit);
        }
      }
      return lookup;
    });
  }

  Future<List<Product>> _resolveSearchProducts(List<Product> fallbackProducts,
      Map<String, String> searchIndex, String query,
      {required int limit, bool stockTrackedOnly = false}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return fallbackProducts;
    }
    final sqlite = await LocalDatabaseService.queryProductsFromSqlite(
        query: normalized,
        limit: limit,
        activeOnly: true,
        stockTrackedOnly: stockTrackedOnly);
    if (sqlite != null) {
      return sqlite.items;
    }
    return fallbackProducts
        .where(
            (product) => searchIndex[product.id]?.contains(normalized) ?? false)
        .take(limit)
        .toList(growable: false);
  }

  void _resetProductSearchReveal() {
    _productSearchRevealTimer?.cancel();
    _productSearchRevealTimer = null;
    _visibleProductsFuture = null;
    _visibleProductsFutureKey = '';
  }

  List<Product> _visibleProducts() {
    final q = _search.trim().toLowerCase();
    return _visibleProductsCache.getOrCompute(widget.store.productsRevision, q,
        () {
      final activeProducts = _activeProductsCache.getOrCompute(
          widget.store.productsRevision,
          'active_products',
          () => widget.store.products
              .where((product) => product.isActive && !product.isDeleted)
              .toList(growable: false));
      if (q.isEmpty) return activeProducts;
      final index = _productSearchIndex();
      return activeProducts
          .where((product) => index[product.id]?.contains(q) ?? false)
          .toList(growable: false);
    });
  }

  Future<List<Product>?> _visibleProductsFromSqlite() {
    if (!LocalDatabaseService.canQueryBusinessSqlite) {
      return Future<List<Product>?>.value(null);
    }
    final normalized = _search.trim().toLowerCase();
    final limit = normalized.isEmpty ? 100 : 250;
    final key = '${widget.store.productsRevision}|$normalized|$limit';
    if (_visibleProductsFuture == null || _visibleProductsFutureKey != key) {
      _visibleProductsFutureKey = key;
      _visibleProductsFuture = () async {
        final page = await LocalDatabaseService.queryProductsFromSqlite(
            query: normalized, limit: limit, activeOnly: true);
        return page?.items;
      }();
    }
    return _visibleProductsFuture!;
  }
}
