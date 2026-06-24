import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/app_user.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../barcode/barcode_scanner_page.dart';

enum _BarcodeAddResult {
  added,
  autoCorrected,
  empty,
  notAllowed,
  notFound,
  outOfStock,
  stockLimitReached,
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _paymentExchangeRateController =
      TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'sale_shortcuts');
  final FocusNode _paymentShortcutFocusNode =
      FocusNode(debugLabel: 'sale_payment_shortcuts');
  final FocusNode _discountFocusNode =
      FocusNode(debugLabel: 'sale_payment_discount');
  final FocusNode _cashReceivedFocusNode =
      FocusNode(debugLabel: 'sale_payment_cash_received');

  static const String _quickPagesStorageKey = 'sale_quick_product_pages_v1';
  static const String _heldSalesStorageKey = 'sale_held_carts_v1';

  final List<_DraftSaleItem> _cart = [];
  final List<_QuickProductPage> _quickPages = [];
  String _selectedCustomerId = AppStore.walkInCustomerId;
  String _paymentMethod = 'Cash';
  String _invoiceCurrency = 'USD';
  String _paymentCurrency = 'USD';
  String _discountCurrency = 'USD';
  String _search = '';
  final List<_HeldSaleCart> _heldCarts = [];
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    cameraResolution: const Size(1280, 720),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 500,
  );
  bool _scannerActive = false;
  bool _scannerStartFailed = false;
  bool _manualBarcodeInput = false;
  bool _quickGridEditMode = false;
  List<_QuickProductPage>? _quickPagesEditSnapshot;
  int _selectedQuickPageIndex = 0;
  String? _lastScannedCode;
  DateTime? _lastScannedAt;
  int _cashShiftRefreshKey = 0;
  int? _selectedCartIndex;
  int? _pendingDeleteCartIndex;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = AppStore.walkInCustomerId;
    _invoiceCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
    _paymentCurrency = widget.store.storeProfile.defaultSalePaymentCurrency;
    _discountCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
    _paymentExchangeRateController.text =
        widget.store.storeProfile.usdToLbpRate.toStringAsFixed(0);
    _loadQuickProductPages();
    _loadHeldSaleCarts();
    HardwareKeyboard.instance.addHandler(_handleSaleHardwareShortcutKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _manualBarcodeInput) return;
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleSaleHardwareShortcutKey);
    _searchController.dispose();
    _barcodeController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    _paymentExchangeRateController.dispose();
    _barcodeFocusNode.dispose();
    _shortcutFocusNode.dispose();
    _paymentShortcutFocusNode.dispose();
    _discountFocusNode.dispose();
    _cashReceivedFocusNode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  double get _discount {
    final value = double.tryParse(_discountController.text) ?? 0;
    final normalized = value < 0 ? 0 : value;
    return toUsdReferencePrice(
        normalized.toDouble(), _discountCurrency, widget.store.storeProfile);
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);
  String _stockAvailabilityLabel(Product product, AppLocalizations tr,
      {bool includeUnit = false}) {
    if (!product.trackStock) return 'Non-stock';
    final quantity =
        includeUnit ? _formatQuantity(product.stock) : product.stock.toString();
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
      _paymentCurrency,
      _invoiceCurrency,
      widget.store.storeProfile,
      effectiveAt: DateTime.now(),
    );
  }

  double get _rawInvoiceTotal => _currencyFromBase(_total, _invoiceCurrency);

  /// Final invoice amount after cash rounding.
  /// Cash rounding is applied only to cash sales and only on the actual
  /// payment currency, then converted back to the invoice currency so the
  /// sale screen, validation, and persisted sale use the same payable amount.
  double get _invoiceTotal {
    final rawTotal = _rawInvoiceTotal;
    if (!_isCashPayment) return rawTotal;
    final amountInPaymentCurrency = _convertCurrencyAmount(
      rawTotal,
      _invoiceCurrency,
      _paymentCurrency,
    );
    final roundedPaymentAmount = normalizeCashAmount(
      amountInPaymentCurrency,
      _paymentCurrency,
      widget.store.storeProfile,
    );
    return _convertCurrencyAmount(
      roundedPaymentAmount,
      _paymentCurrency,
      _invoiceCurrency,
    );
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
        effectiveAt: DateTime.now(),
      );

  double _convertCurrencyAmount(
      double amount, String fromCurrency, String toCurrency) {
    return convertCurrency(
      amount,
      fromCurrency,
      toCurrency,
      widget.store.storeProfile,
      effectiveAt: DateTime.now(),
    );
  }

  String _formatSaleCurrency(double amount, String currency) =>
      formatCurrency(amount, currency: currency);

  List<Product> _visibleProducts() {
    final q = _search.trim().toLowerCase();
    return widget.store.products
        .where((product) => product.isActive && !product.isDeleted)
        .where((product) {
      if (q.isEmpty) return true;
      return product.name.toLowerCase().contains(q) ||
          product.code.toLowerCase().contains(q) ||
          product.barcode.toLowerCase().contains(q) ||
          product.effectiveSaleUnits
              .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
          product.effectivePurchaseUnits
              .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
          product.category.toLowerCase().contains(q);
    }).toList();
  }

  bool _handleSaleHardwareShortcutKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    return _handleSaleShortcutKey(event, _visibleProducts());
  }

  bool _handleSaleShortcutKey(KeyEvent event, List<Product> visibleProducts) {
    if (event is! KeyDownEvent) return false;
    if (_handleCartArrowKey(event)) return true;
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return false;
    final action = SaleShortcutSettings.load().saleActionForKey(keyName);
    if (action == null) return false;
    _executeSaleShortcut(action, visibleProducts);
    return true;
  }

  bool _handleCartArrowKey(KeyDownEvent event) {
    if (_cart.isEmpty || !_canHandleCartArrowKeys()) return false;
    if (event.logicalKey != LogicalKeyboardKey.arrowUp &&
        event.logicalKey != LogicalKeyboardKey.arrowDown &&
        event.logicalKey != LogicalKeyboardKey.arrowLeft &&
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }

    final currentIndex = _normalizedSelectedCartIndex();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _selectCartIndex((currentIndex - 1).clamp(0, _cart.length - 1).toInt());
        return true;
      case LogicalKeyboardKey.arrowDown:
        _selectCartIndex((currentIndex + 1).clamp(0, _cart.length - 1).toInt());
        return true;
      case LogicalKeyboardKey.arrowLeft:
        if (Directionality.of(context) == TextDirection.rtl) {
          _increaseSelectedCartItem();
        } else {
          _decreaseOrMarkSelectedCartItem();
        }
        return true;
      case LogicalKeyboardKey.arrowRight:
        if (Directionality.of(context) == TextDirection.rtl) {
          _decreaseOrMarkSelectedCartItem();
        } else {
          _increaseSelectedCartItem();
        }
        return true;
    }
    return false;
  }

  bool _canHandleCartArrowKeys() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null || primaryFocus == _barcodeFocusNode) return true;
    final focusContext = primaryFocus.context;
    if (focusContext == null) return true;
    final isEditable = focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
    return !isEditable;
  }

  int _normalizedSelectedCartIndex() {
    if (_cart.isEmpty) return 0;
    final index = _selectedCartIndex ?? 0;
    return index.clamp(0, _cart.length - 1).toInt();
  }

  void _selectCartIndex(int index) {
    if (_cart.isEmpty) return;
    setState(() {
      _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
      _pendingDeleteCartIndex = null;
    });
  }

  void _increaseSelectedCartItem() {
    if (_cart.isEmpty) return;
    final index = _normalizedSelectedCartIndex();
    final item = _cart[index];
    _changeCartQuantity(index, item.quantity + 1);
  }

  void _decreaseOrMarkSelectedCartItem() {
    if (_cart.isEmpty) return;
    _decreaseOrMarkCartItem(_normalizedSelectedCartIndex());
  }

  void _decreaseOrMarkCartItem(int index) {
    if (index < 0 || index >= _cart.length) return;
    final item = _cart[index];
    if (item.quantity > 1) {
      _changeCartQuantity(index, item.quantity - 1);
      return;
    }
    if (_pendingDeleteCartIndex == index) {
      setState(() {
        _cart.removeAt(index);
        _pendingDeleteCartIndex = null;
        if (_cart.isEmpty) {
          _selectedCartIndex = null;
        } else {
          _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
        }
      });
      return;
    }
    setState(() {
      _selectedCartIndex = index;
      _pendingDeleteCartIndex = index;
    });
  }

  void _removeCartItem(int index) {
    if (index < 0 || index >= _cart.length) return;
    setState(() {
      _cart.removeAt(index);
      _pendingDeleteCartIndex = null;
      if (_cart.isEmpty) {
        _selectedCartIndex = null;
      } else {
        _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
      }
    });
  }

  Future<void> _executeSaleShortcut(
      SaleShortcutAction action, List<Product> visibleProducts) async {
    final tr = AppLocalizations.of(context);
    switch (action) {
      case SaleShortcutAction.focusBarcode:
        _restoreScannerMode();
        break;
      case SaleShortcutAction.searchProduct:
        _showProductSearchSheet(visibleProducts);
        break;
      case SaleShortcutAction.holdCart:
        if (_cart.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr.text('shortcut_cart_empty'))));
          return;
        }
        await _holdCurrentCart();
        break;
      case SaleShortcutAction.restoreHeldCarts:
        await _showHeldCartsDialog();
        break;
      case SaleShortcutAction.openPayment:
        if (_cart.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr.text('shortcut_cart_empty'))));
          return;
        }
        await _openPaymentPage(printAfterSave: false);
        break;
      case SaleShortcutAction.clearCart:
        await _confirmClearCart();
        break;
    }
  }

  bool _handlePaymentShortcutKey(KeyEvent event, BuildContext dialogContext,
      void Function(void Function()) setDialogState) {
    if (event is! KeyDownEvent) return false;
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return false;
    final action = SaleShortcutSettings.load().paymentActionForKey(keyName);
    if (action == null) return false;
    switch (action) {
      case SalePaymentShortcutAction.confirmPayment:
        Navigator.pop(dialogContext, true);
        return true;
      case SalePaymentShortcutAction.cancelPayment:
        Navigator.pop(dialogContext, false);
        return true;
      case SalePaymentShortcutAction.focusDiscount:
        _discountFocusNode.requestFocus();
        return true;
      case SalePaymentShortcutAction.focusCashReceived:
        if (_showsCashReceived) {
          _cashReceivedFocusNode.requestFocus();
        }
        return true;
      case SalePaymentShortcutAction.toggleCash:
        _setPaymentMethod('Cash');
        setDialogState(() {});
        return true;
      case SalePaymentShortcutAction.toggleCard:
        _setPaymentMethod('Card');
        setDialogState(() {});
        return true;
      case SalePaymentShortcutAction.toggleCredit:
        _setPaymentMethod('Credit');
        setDialogState(() {});
        return true;
    }
  }

  Widget _buildPaymentShortcutGuide(BuildContext context, AppLocalizations tr) {
    final settings = SaleShortcutSettings.load();
    final chips = <Widget>[];
    for (final action in SalePaymentShortcutAction.values) {
      final keyName = settings.keyForPaymentAction(action);
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

  Future<void> _confirmClearCart() async {
    if (_cart.isEmpty) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('clear_cart')),
        content: Text(tr.text('confirm_clear_cart')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr.text('clear'))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _cart.clear();
        _selectedCartIndex = null;
        _pendingDeleteCartIndex = null;
      });
      _restoreScannerMode();
    }
  }

  void _setSelectedCustomerId(String? value) {
    final id = widget.store.sanitizeSelectedCustomerId(value);
    setState(() {
      _selectedCustomerId = id;
      if (id == AppStore.walkInCustomerId && _paymentMethod == 'Credit') {
        _paymentMethod = 'Cash';
        _paidAmountController.clear();
      }
    });
  }

  void _setPaymentMethod(String value) {
    setState(() {
      _paymentMethod =
          (_isWalkInCustomer && value == 'Credit') ? 'Cash' : value;
      if (_paymentMethod == 'Cash') {
        _paidAmountController.clear();
      } else if (_paidAmountController.text.trim().isEmpty) {
        _paidAmountController.text = '0';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final sales = widget.store.sales;
    final products = _visibleProducts();

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 980;
          final pagePadding = VentioResponsive.pagePadding(context);

          if (!isWide) {
            return _buildMobileSalesLayout(context, tr, products, pagePadding);
          }

          return _buildDesktopSalesLayout(
              context, tr, products, sales, pagePadding);
        },
      ),
    );
  }

  Customer _selectedCustomer() {
    final id = widget.store.sanitizeSelectedCustomerId(_selectedCustomerId);
    return widget.store.customers.firstWhere(
      (customer) => customer.id == id,
      orElse: () => widget.store.walkInCustomer,
    );
  }

  String _customerSearchText(Customer customer) {
    final phone = customer.phone.trim();
    final id = customer.id.trim();
    if (customer.id == AppStore.walkInCustomerId) return customer.name;
    return phone.isEmpty
        ? '#$id - ${customer.name}'
        : '#$id - ${customer.name} - $phone';
  }

  List<Customer> _customerSearchOptions(String query) {
    final normalized = query.trim().toLowerCase();
    final seen = <String>{};
    final customers = <Customer>[];
    for (final customer in [
      widget.store.walkInCustomer,
      ...widget.store.customers
    ]) {
      if (!seen.add(customer.id)) continue;
      if (normalized.isEmpty ||
          customer.name.toLowerCase().contains(normalized) ||
          customer.phone.toLowerCase().contains(normalized) ||
          customer.id.toLowerCase().contains(normalized)) {
        customers.add(customer);
      }
    }
    customers.sort((a, b) {
      if (a.id == AppStore.walkInCustomerId) return -1;
      if (b.id == AppStore.walkInCustomerId) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return customers.take(20).toList();
  }

  Widget _buildCustomerSelector(BuildContext context, AppLocalizations tr,
      {bool dense = false, void Function(void Function())? modalSetState}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RawAutocomplete<Customer>(
            key: ValueKey(
                'sale_customer_${_selectedCustomerId}_${widget.store.customers.length}'),
            initialValue: TextEditingValue(
                text: _customerSearchText(_selectedCustomer())),
            displayStringForOption: _customerSearchText,
            optionsBuilder: (value) => _customerSearchOptions(value.text),
            onSelected: (customer) {
              _setSelectedCustomerId(customer.id);
              modalSetState?.call(() {});
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: tr.text('customer'),
                  hintText: '${tr.text('search')} / phone / ID',
                  isDense: dense,
                  prefixIcon: const Icon(Icons.search),
                ),
                onTap: () => controller.selection = TextSelection(
                    baseOffset: 0, extentOffset: controller.text.length),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final list = options.toList();
              return Align(
                alignment: AlignmentDirectional.topStart,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 280, maxWidth: 520),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = list[index];
                        final isWalkIn =
                            customer.id == AppStore.walkInCustomerId;
                        final phone = customer.phone.trim();
                        return ListTile(
                          dense: true,
                          leading: Icon(isWalkIn
                              ? Icons.person_outline
                              : Icons.badge_outlined),
                          title: Text(
                              isWalkIn
                                  ? customer.name
                                  : '#${customer.id} - ${customer.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: isWalkIn || phone.isEmpty
                              ? null
                              : Text(phone,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => onSelected(customer),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () async {
            final id = await _showQuickCustomerDialog(context, tr);
            if (id == null || !mounted) return;
            _setSelectedCustomerId(id);
            modalSetState?.call(() {});
          },
          icon: const Icon(Icons.person_add_alt_1),
          tooltip: tr.text('add_customer'),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodChips(AppLocalizations tr,
      {void Function(void Function())? modalSetState}) {
    final methods = <MapEntry<String, String>>[
      MapEntry('Cash', tr.text('payment_cash')),
      if (!_isWalkInCustomer) MapEntry('Credit', tr.text('credit_unpaid')),
      MapEntry('Card', tr.text('payment_card')),
      MapEntry('Wish', tr.text('payment_wish')),
      MapEntry('Check', tr.text('payment_check')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('payment_method'),
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in methods)
              ChoiceChip(
                label: Text(method.value),
                selected: _paymentMethod == method.key,
                onSelected: (_) {
                  _setPaymentMethod(method.key);
                  modalSetState?.call(() {});
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentCurrencySwitch(AppLocalizations tr,
      {void Function(void Function())? modalSetState}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('payment_currency'),
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final fullWidth = constraints.maxWidth < 420;
            final currencies = widget.store.storeProfile.currencies
                .where((item) => item.isActive)
                .toList(growable: false);
            final children = [
              for (final currency in currencies)
                ChoiceChip(
                  label: Text(currency.code),
                  selected: _paymentCurrency == currency.code,
                  onSelected: (_) {
                    setState(() => _paymentCurrency = currency.code);
                    modalSetState?.call(() {});
                  },
                ),
            ];
            if (!fullWidth) {
              return Wrap(spacing: 8, runSpacing: 8, children: children);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCashReceivedField(AppLocalizations tr,
      {bool dense = false, void Function(void Function())? modalSetState}) {
    return TextFormField(
      focusNode: _cashReceivedFocusNode,
      controller: _paidAmountController,
      decoration: InputDecoration(
          labelText: '${tr.text('paid_amount')} ($_paymentCurrency)',
          isDense: dense),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))
      ],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        setState(() {});
        modalSetState?.call(() {});
      },
    );
  }

  Future<String?> _showQuickCustomerDialog(
      BuildContext context, AppLocalizations tr) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final customer = await showDialog<Customer>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr.text('add_customer')),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration:
                        InputDecoration(labelText: tr.text('customer_name')),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? tr.text('required_field')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone'))),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: addressController,
                      decoration:
                          InputDecoration(labelText: tr.text('address'))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  Customer(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    address: addressController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      );
      if (customer == null) return null;
      if (!context.mounted) return null;
      final messenger = ScaffoldMessenger.of(context);
      final createdMessage = tr.text('customer_created_selected');
      await widget.store.addOrUpdateCustomer(customer);
      if (!context.mounted) return null;
      messenger.showSnackBar(SnackBar(content: Text(createdMessage)));
      return customer.id;
    } catch (_) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('customer_save_failed'))));
      }
      return null;
    } finally {
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
    }
  }

  Widget _buildShortcutGuide(BuildContext context, AppLocalizations tr) {
    final settings = SaleShortcutSettings.load();
    final chips = <Widget>[];
    for (final action in SaleShortcutAction.values) {
      final keyName = settings.keyForSaleAction(action);
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

  String _activeUserDisplayName([AppUser? user]) {
    final current = user ?? widget.store.activeUser;
    final fullName = current?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final username = current?.username.trim() ?? '';
    if (username.isNotEmpty) return username;
    return widget.store.currentRole;
  }

  Future<_SaleShiftStatus> _loadSaleShiftStatus() async {
    final locations = await AccountingService.listActiveCashLocations();
    final openSessions = await AccountingService.listOpenCashDrawersReport();
    final deviceId = widget.store.appIdentity.deviceId.trim();
    final branchId = widget.store.appIdentity.branchId.trim();
    final linkedDrawers = locations
        .where((item) =>
            item.type == 'cash_drawer' &&
            deviceId.isNotEmpty &&
            item.referenceId == deviceId)
        .toList(growable: false);
    final allDrawers = locations
        .where((item) => item.type == 'cash_drawer')
        .toList(growable: false);
    final drawer = linkedDrawers.isNotEmpty
        ? linkedDrawers.first
        : (allDrawers.isNotEmpty ? allDrawers.first : null);
    AdvancedAccountingItem? openSession;
    if (drawer != null) {
      for (final item in openSessions) {
        if (item.referenceId == drawer.id) {
          openSession = item;
          break;
        }
      }
    }
    return _SaleShiftStatus(
      drawer: drawer,
      openSession: openSession,
      drawers: allDrawers,
      cashLocations: locations,
      branchId: branchId,
    );
  }

  Widget _buildSaleShiftStatusCard(BuildContext context, AppLocalizations tr) {
    return FutureBuilder<_SaleShiftStatus>(
      key: ValueKey('sale_shift_status_$_cashShiftRefreshKey'),
      future: _loadSaleShiftStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        final openSession = status?.openSession;
        final drawer = status?.drawer;
        final isLoading = snapshot.connectionState != ConnectionState.done;
        final colorScheme = Theme.of(context).colorScheme;
        final title = openSession == null
            ? 'لا توجد وردية نقدية مفتوحة'
            : 'الوردية النقدية مفتوحة';
        final subtitle = openSession == null
            ? (drawer == null
                ? 'لا يوجد درج نقدية مربوط أو معرف لهذا الجهاز.'
                : 'الدرج: ${drawer.name} • افتح وردية قبل البيع النقدي.')
            : '${openSession.name} • ${openSession.accountName.isEmpty ? 'درج نقدية' : openSession.accountName} • المتوقع: ${formatUsdReferenceAmount(openSession.credit, widget.store.storeProfile)}';
        return Card(
          elevation: 0,
          color: openSession == null
              ? colorScheme.errorContainer.withValues(alpha: 0.25)
              : colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  openSession == null
                      ? Icons.lock_open_outlined
                      : Icons.point_of_sale_outlined,
                  color: openSession == null
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (openSession == null)
                  FilledButton.icon(
                    onPressed: status == null || status.drawers.isEmpty
                        ? null
                        : () => _openSaleDrawerDialog(status),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('فتح وردية'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: status == null
                            ? null
                            : () => _closeSaleDrawerDialog(openSession, status),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('إغلاق / تسليم'),
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

  Future<void> _showSaleShiftQuickAction() async {
    final tr = AppLocalizations.of(context);
    try {
      final status = await _loadSaleShiftStatus();
      if (!mounted) return;
      final openSession = status.openSession;
      if (openSession == null) {
        if (status.drawers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'لا يوجد درج نقدية معرف. أضف درج نقدية أولاً من الإعدادات المالية.'),
            ),
          );
          return;
        }
        await _openSaleDrawerDialog(status);
      } else {
        await _closeSaleDrawerDialog(openSession, status);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    }
  }

  Future<void> _openSaleDrawerDialog(_SaleShiftStatus status) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: '0');
    final drawers = status.drawers;
    final sources = status.cashLocations
        .where((item) => item.type != 'cash_drawer')
        .toList(growable: false);
    String selectedDrawerId = (status.drawer?.id ?? '').isNotEmpty
        ? status.drawer!.id
        : (drawers.isNotEmpty ? drawers.first.id : '');
    String selectedFundingId = sources.isNotEmpty ? sources.first.id : '';
    bool useFundingSource = sources.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('فتح وردية نقدية'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      selectedDrawerId.isEmpty ? null : selectedDrawerId,
                  decoration: const InputDecoration(labelText: 'درج النقدية'),
                  items: drawers
                      .map((item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedDrawerId = value ?? ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'مبلغ الافتتاح'),
                ),
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تحويل مبلغ الافتتاح من صندوق آخر'),
                    value: useFundingSource,
                    onChanged: (value) =>
                        setDialogState(() => useFundingSource = value),
                  ),
                  if (useFundingSource)
                    DropdownButtonFormField<String>(
                      initialValue:
                          selectedFundingId.isEmpty ? null : selectedFundingId,
                      decoration:
                          const InputDecoration(labelText: 'مصدر المبلغ'),
                      items: sources
                          .map((item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedFundingId = value ?? ''),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: selectedDrawerId.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('فتح'),
            ),
          ],
        ),
      ),
    );
    try {
      if (confirmed == true) {
        final drawer =
            drawers.firstWhere((item) => item.id == selectedDrawerId);
        final activeUser = widget.store.activeUser;
        await AccountingService.openCashDrawer(
          drawerNo: drawer.name,
          cashLocationId: drawer.id,
          fundingLocationId: useFundingSource ? selectedFundingId : '',
          openingBalance: double.tryParse(controller.text.trim()) ?? 0,
          openedBy: _activeUserDisplayName(activeUser),
          openedByUserId: activeUser?.id ?? '',
          storeId: widget.store.appIdentity.storeId,
          branchId: widget.store.appIdentity.branchId,
          deviceId: widget.store.appIdentity.deviceId,
        );
        if (!mounted) return;
        setState(() => _cashShiftRefreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم فتح الوردية النقدية')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _closeSaleDrawerDialog(
      AdvancedAccountingItem session, _SaleShiftStatus status) async {
    final tr = AppLocalizations.of(context);
    final expected =
        await AccountingService.calculateCashDrawerExpectedCash(session.id);
    if (!mounted) return;
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final notes = TextEditingController();
    final transferTargets = status.cashLocations
        .where((item) => item.id != session.referenceId)
        .toList(growable: false);
    final activeUser = widget.store.activeUser;
    final handoverUsers = widget.store.users
        .where((user) => user.isActive && user.id != (activeUser?.id ?? ''))
        .toList(growable: false);
    String closeMode = 'keep_drawer';
    String transferToId =
        transferTargets.isNotEmpty ? transferTargets.first.id : '';
    String nextUserId = handoverUsers.isNotEmpty ? handoverUsers.first.id : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('إغلاق / تسليم الوردية'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    'المتوقع: ${formatUsdReferenceAmount(expected, widget.store.storeProfile)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: counted,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'المبلغ المعدود'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: closeMode,
                  decoration: const InputDecoration(labelText: 'طريقة الإغلاق'),
                  items: const [
                    DropdownMenuItem(
                      value: 'keep_drawer',
                      child: Text('إغلاق فقط وترك النقد بنفس الدرج'),
                    ),
                    DropdownMenuItem(
                      value: 'transfer_location',
                      child: Text('إغلاق وتحويل النقد إلى درج/صندوق آخر'),
                    ),
                    DropdownMenuItem(
                      value: 'handover_user',
                      child: Text('تسليم لموظف جديد وفتح وردية جديدة'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => closeMode = value ?? closeMode),
                ),
                if (closeMode == 'transfer_location') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: transferToId.isEmpty ? null : transferToId,
                    decoration: const InputDecoration(
                        labelText: 'الدرج / الصندوق المستلم'),
                    items: transferTargets
                        .map((item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => transferToId = value ?? ''),
                  ),
                ],
                if (closeMode == 'handover_user') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: nextUserId.isEmpty ? null : nextUserId,
                    decoration:
                        const InputDecoration(labelText: 'الموظف المستلم'),
                    items: handoverUsers
                        .map((user) => DropdownMenuItem(
                              value: user.id,
                              child: Text(_activeUserDisplayName(user)),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => nextUserId = value ?? ''),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'سيتم إغلاق الوردية الحالية وفتح وردية جديدة للموظف المستلم بنفس المبلغ المعدود.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: tr.text('notes')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed:
                  (closeMode == 'transfer_location' && transferToId.isEmpty) ||
                          (closeMode == 'handover_user' && nextUserId.isEmpty)
                      ? null
                      : () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('close')),
            ),
          ],
        ),
      ),
    );
    try {
      if (confirmed == true) {
        final countedAmount = double.tryParse(counted.text.trim()) ?? 0;
        final activeUserName = _activeUserDisplayName(activeUser);
        AppUser? nextUser;
        for (final user in handoverUsers) {
          if (user.id == nextUserId) {
            nextUser = user;
            break;
          }
        }
        String transferTargetName = '';
        for (final location in transferTargets) {
          if (location.id == transferToId) transferTargetName = location.name;
        }
        final nextUserName =
            nextUser == null ? '' : _activeUserDisplayName(nextUser);
        final effectiveNotes = [
          notes.text.trim(),
          if (closeMode == 'transfer_location')
            'تحويل النقد بعد الإغلاق إلى $transferTargetName',
          if (closeMode == 'handover_user') 'تسليم الوردية إلى $nextUserName',
        ].where((part) => part.trim().isNotEmpty).join(' • ');
        await AccountingService.closeCashDrawer(
          sessionId: session.id,
          countedCash: countedAmount,
          closedBy: activeUserName,
          closedByUserId: activeUser?.id ?? '',
          notes: effectiveNotes,
          depositToLocationId:
              closeMode == 'transfer_location' ? transferToId : '',
        );
        if (closeMode == 'handover_user' &&
            nextUser != null &&
            session.referenceId.trim().isNotEmpty) {
          await AccountingService.openCashDrawer(
            drawerNo: session.name,
            cashLocationId: session.referenceId,
            openingBalance: countedAmount,
            openedBy: nextUserName,
            openedByUserId: nextUser.id,
            storeId: widget.store.appIdentity.storeId,
            branchId: widget.store.appIdentity.branchId,
            deviceId: widget.store.appIdentity.deviceId,
          );
        }
        if (!mounted) return;
        setState(() => _cashShiftRefreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الوردية النقدية')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      counted.dispose();
      notes.dispose();
    }
  }

  Widget _buildDesktopSalesLayout(BuildContext context, AppLocalizations tr,
      List<Product> products, List<Sale> sales, double pagePadding) {
    return Padding(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('pos_terminal'),
            subtitle: tr.text('pos_terminal_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _showSaleShiftQuickAction,
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: const Text('إدارة الوردية'),
                ),
                OutlinedButton.icon(
                  onPressed: _showInvoicesSheet,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(tr.text('recent_invoices')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildShortcutGuide(context, tr),
          const SizedBox(height: 8),
          _buildSaleShiftStatusCard(context, tr),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    flex: 6,
                    child: _buildCurrentSalePanel(context, tr, products)),
                const SizedBox(width: 12),
                Expanded(
                    flex: 4,
                    child: _buildQuickProductGridPanel(context, tr, products)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentSalePanel(
      BuildContext context, AppLocalizations tr, List<Product> products) {
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
            const SizedBox(height: 12),
            _buildSaleTotalBar(context, tr),
          ],
        ),
      ),
    );
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
            Row(
              children: [
                Expanded(
                    child: Text(tr.text('quick_product_grid'),
                        style: Theme.of(context).textTheme.titleLarge)),
                if (_quickGridEditMode) ...[
                  TextButton.icon(
                    onPressed: _cancelQuickGridEditing,
                    icon: const Icon(Icons.close),
                    label: Text(tr.text('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saveQuickGridEditing,
                    icon: const Icon(Icons.check),
                    label: Text(tr.text('save')),
                  ),
                ] else
                  TextButton.icon(
                    onPressed: _startQuickGridEditing,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr.text('edit_layout')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: Row(
                children: [
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
                              final selected = index == _selectedQuickPageIndex;
                              return Padding(
                                key: ValueKey(
                                    'quick_page_${index}_${_quickPages[index].name}'),
                                padding:
                                    const EdgeInsetsDirectional.only(end: 8),
                                child: ReorderableDragStartListener(
                                  index: index,
                                  child: InputChip(
                                    avatar: const Icon(Icons.drag_indicator,
                                        size: 18),
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 120),
                                            child: Text(_quickPages[index].name,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit_outlined,
                                            size: 16),
                                      ],
                                    ),
                                    selected: selected,
                                    onSelected: (_) {
                                      if (selected) {
                                        _renameQuickPage(index);
                                      } else {
                                        setState(() =>
                                            _selectedQuickPageIndex = index);
                                      }
                                    },
                                    deleteIcon: _quickPages.length > 1
                                        ? const Icon(Icons.close, size: 18)
                                        : null,
                                    onDeleted: _quickPages.length > 1
                                        ? () => _deleteQuickPage(index)
                                        : null,
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _quickPages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final selected = index == _selectedQuickPageIndex;
                              return InputChip(
                                label: Text(_quickPages[index].name),
                                selected: selected,
                                onSelected: (_) => setState(
                                    () => _selectedQuickPageIndex = index),
                              );
                            },
                          ),
                  ),
                  if (_quickGridEditMode) ...[
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(tr.text('page')),
                      onPressed: _addQuickPage,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visibleSlotIndexes.isEmpty
                  ? Center(child: Text(tr.text('no_products')))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount =
                            constraints.maxWidth > 520 ? 3 : 2;
                        return GridView.builder(
                          itemCount: visibleSlotIndexes.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.18,
                          ),
                          itemBuilder: (context, visibleIndex) {
                            final slotIndex = visibleSlotIndexes[visibleIndex];
                            final slot = page.slots[slotIndex];
                            final product = slot.productId == null
                                ? null
                                : _productById(slot.productId!);
                            final isEmpty = product == null;
                            final child = _buildQuickProductTile(context, tr,
                                page, slotIndex, slot, product, isEmpty);
                            if (!_quickGridEditMode) return child;
                            final target = DragTarget<int>(
                              onWillAcceptWithDetails: (details) =>
                                  details.data != slotIndex,
                              onAcceptWithDetails: (details) =>
                                  _moveQuickSlot(details.data, slotIndex),
                              builder: (_, candidateData, ___) {
                                if (candidateData.isEmpty) return child;
                                return DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                  ),
                                  child: child,
                                );
                              },
                            );
                            if (isEmpty) return target;
                            return LongPressDraggable<int>(
                              data: slotIndex,
                              feedback: Material(
                                elevation: 6,
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                    width: 150, height: 120, child: child),
                              ),
                              childWhenDragging:
                                  Opacity(opacity: 0.35, child: child),
                              child: target,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickProductTile(
      BuildContext context,
      AppLocalizations tr,
      _QuickProductPage page,
      int index,
      _QuickProductSlot slot,
      Product? product,
      bool isEmpty,
      {VoidCallback? onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        if (isEmpty) {
          if (_quickGridEditMode) {
            await _configureQuickSlot(page, index);
            onChanged?.call();
          }
        } else if (_quickGridEditMode) {
          await _configureQuickSlot(page, index);
          onChanged?.call();
        } else {
          _addProduct(product!);
        }
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isEmpty
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
              : scheme.primaryContainer.withValues(alpha: 0.40),
          border: Border.all(
              color: isEmpty
                  ? scheme.outlineVariant
                  : scheme.primary.withValues(alpha: 0.28)),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: isEmpty
                    ? Icon(Icons.add, size: 34, color: scheme.primary)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              slot.shortName?.trim().isNotEmpty == true
                                  ? slot.shortName!.trim()
                                  : product!.name,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                              formatUsdReferenceAmount(
                                  product!.price, widget.store.storeProfile),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
              ),
            ),
            if (_quickGridEditMode && !isEmpty)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: tr.text('delete'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _clearQuickSlot(page, index);
                    onChanged?.call();
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            if (_quickGridEditMode && !isEmpty)
              const Positioned(
                  left: 8,
                  bottom: 8,
                  child: Icon(Icons.drag_indicator, size: 20)),
            if (_quickGridEditMode && !isEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child:
                    Icon(Icons.edit_outlined, size: 20, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  List<int> _quickVisibleSlotIndexes(_QuickProductPage page) {
    final filled = <int>[];
    int? firstEmpty;
    for (var i = 0; i < page.slots.length; i += 1) {
      final slot = page.slots[i];
      final product =
          slot.productId == null ? null : _productById(slot.productId!);
      if (product != null) {
        filled.add(i);
      } else {
        firstEmpty ??= i;
      }
    }
    if (_quickGridEditMode && firstEmpty != null) filled.add(firstEmpty);
    return filled;
  }

  List<_QuickProductPage> _cloneQuickPages(List<_QuickProductPage> pages) {
    return pages
        .map(
          (page) => _QuickProductPage(
            name: page.name,
            slots: page.slots
                .map((slot) => _QuickProductSlot(
                    productId: slot.productId, shortName: slot.shortName))
                .toList(),
          ),
        )
        .toList();
  }

  bool get _quickGridHasUnsavedChanges {
    final snapshot = _quickPagesEditSnapshot;
    if (snapshot == null) return false;
    return jsonEncode(snapshot.map((page) => page.toJson()).toList()) !=
        jsonEncode(_quickPages.map((page) => page.toJson()).toList());
  }

  void _startQuickGridEditing() {
    setState(() {
      _quickPagesEditSnapshot ??= _cloneQuickPages(_quickPages);
      _quickGridEditMode = true;
    });
  }

  void _saveQuickGridEditing() {
    setState(() {
      _quickGridEditMode = false;
      _quickPagesEditSnapshot = null;
    });
    unawaited(_saveQuickProductPages());
  }

  void _cancelQuickGridEditing() {
    final snapshot = _quickPagesEditSnapshot;
    setState(() {
      if (snapshot != null) {
        _quickPages
          ..clear()
          ..addAll(_cloneQuickPages(snapshot));
      }
      _quickGridEditMode = false;
      _quickPagesEditSnapshot = null;
      _selectedQuickPageIndex =
          _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    });
  }

  Future<bool> _confirmCloseQuickGridEditor() async {
    if (!_quickGridEditMode) return true;
    if (!_quickGridHasUnsavedChanges) {
      _cancelQuickGridEditing();
      return true;
    }
    final tr = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('unsaved_changes')),
        content: Text(tr.text('quick_grid_unsaved_changes_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'stay'),
              child: Text(tr.text('continue_editing'))),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: Text(tr.text('discard_changes'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(tr.text('save'))),
        ],
      ),
    );
    if (result == 'save') {
      _saveQuickGridEditing();
      return true;
    }
    if (result == 'discard') {
      _cancelQuickGridEditing();
      return true;
    }
    return false;
  }

  void _loadQuickProductPages() {
    final raw = LocalDatabaseService.getString(_quickPagesStorageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _quickPages
        ..clear()
        ..addAll(decoded
            .whereType<Map<String, dynamic>>()
            .map(_QuickProductPage.fromJson));
    } catch (_) {
      _quickPages.clear();
    }
  }

  void _ensureQuickPages(List<Product> products, AppLocalizations tr) {
    if (_quickPages.isEmpty) {
      _quickPages.add(
        _QuickProductPage(
          name: tr.text('favorites'),
          slots: List.generate(12, (index) {
            if (index < products.length && index < 6) {
              final product = products[index];
              return _QuickProductSlot(
                  productId: product.id,
                  shortName: _shortProductName(product.name));
            }
            return const _QuickProductSlot();
          }),
        ),
      );
      unawaited(_saveQuickProductPages());
    }
    if (_selectedQuickPageIndex >= _quickPages.length) {
      _selectedQuickPageIndex = _quickPages.length - 1;
    }
    if (_selectedQuickPageIndex < 0) _selectedQuickPageIndex = 0;
  }

  Future<void> _saveQuickProductPages() => LocalDatabaseService.setString(
        _quickPagesStorageKey,
        jsonEncode(_quickPages.map((page) => page.toJson()).toList()),
      );

  String _shortProductName(String name) {
    final clean = name.trim();
    if (clean.length <= 14) return clean;
    return clean.substring(0, 14).trim();
  }

  Product? _productById(String id) {
    for (final product in widget.store.products) {
      if (product.id == id && product.isActive && !product.isDeleted) {
        return product;
      }
    }
    return null;
  }

  void _addQuickPage() {
    setState(() {
      _quickPages.add(_QuickProductPage(
          name:
              '${AppLocalizations.of(context).text('page')} ${_quickPages.length + 1}',
          slots: List.generate(12, (_) => const _QuickProductSlot())));
      _selectedQuickPageIndex = _quickPages.length - 1;
      _quickGridEditMode = true;
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _deleteQuickPage(int index) {
    if (_quickPages.length <= 1 || index < 0 || index >= _quickPages.length) {
      return;
    }
    setState(() {
      _quickPages.removeAt(index);
      _selectedQuickPageIndex =
          _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  Future<void> _renameQuickPage(int index) async {
    if (index < 0 || index >= _quickPages.length) return;
    final controller = TextEditingController(text: _quickPages[index].name);
    final tr = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('rename_quick_page')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: tr.text('page_name')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(tr.text('save'))),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    setState(() => _quickPages[index].name = result.trim());
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _moveQuickPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _quickPages.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 ||
        newIndex >= _quickPages.length ||
        oldIndex == newIndex) {
      return;
    }
    setState(() {
      final page = _quickPages.removeAt(oldIndex);
      _quickPages.insert(newIndex, page);
      if (_selectedQuickPageIndex == oldIndex) {
        _selectedQuickPageIndex = newIndex;
      } else if (oldIndex < _selectedQuickPageIndex &&
          newIndex >= _selectedQuickPageIndex) {
        _selectedQuickPageIndex -= 1;
      } else if (oldIndex > _selectedQuickPageIndex &&
          newIndex <= _selectedQuickPageIndex) {
        _selectedQuickPageIndex += 1;
      }
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _moveQuickSlot(int fromIndex, int toIndex) {
    if (_selectedQuickPageIndex < 0 ||
        _selectedQuickPageIndex >= _quickPages.length) {
      return;
    }
    final page = _quickPages[_selectedQuickPageIndex];
    if (fromIndex < 0 ||
        fromIndex >= page.slots.length ||
        toIndex < 0 ||
        toIndex >= page.slots.length ||
        fromIndex == toIndex) {
      return;
    }
    setState(() {
      final moved = page.slots.removeAt(fromIndex);
      page.slots.insert(toIndex, moved);
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _clearQuickSlot(_QuickProductPage page, int index) {
    if (index < 0 || index >= page.slots.length) return;
    setState(() => page.slots[index] = const _QuickProductSlot());
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  Future<void> _configureQuickSlot(
      _QuickProductPage page, int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= page.slots.length) return;
    final tr = AppLocalizations.of(context);
    final products = widget.store.products
        .where((product) => product.isActive && !product.isDeleted)
        .toList();
    final nameController =
        TextEditingController(text: page.slots[slotIndex].shortName ?? '');
    final quickSearchController = TextEditingController();
    Product? selected = page.slots[slotIndex].productId == null
        ? null
        : _productById(page.slots[slotIndex].productId!);
    var query = '';
    final result = await showModalBottomSheet<_QuickProductSlot>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = products.where((product) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return product.name.toLowerCase().contains(q) ||
                product.code.toLowerCase().contains(q) ||
                product.barcode.toLowerCase().contains(q) ||
                product.effectiveSaleUnits
                    .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
                product.effectivePurchaseUnits
                    .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
                product.category.toLowerCase().contains(q);
          }).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(tr.text('quick_product_shortcut'),
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                          tooltip: tr.text('close'),
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quickSearchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: tr.text('search_product'),
                        suffixIcon: IconButton(
                          tooltip: tr.text('scan_with_camera'),
                          onPressed: () async {
                            final code = await _scanCodeWithCameraOnce();
                            if (code == null) return;
                            quickSearchController.text = code;
                            setSheetState(() => query = code);
                          },
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration:
                          InputDecoration(labelText: tr.text('short_name')),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(tr.text('no_products')))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = filtered[index];
                                final isSelected = selected?.id == product.id;
                                return ListTile(
                                  selected: isSelected,
                                  leading: Icon(isSelected
                                      ? Icons.check_circle
                                      : Icons.inventory_2_outlined),
                                  title: Text(product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${product.code} • ${_stockAvailabilityLabel(product, tr)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: Text(formatUsdReferenceAmount(
                                      widget.store
                                          .defaultProductUsdPrice(product),
                                      widget.store.storeProfile)),
                                  onTap: () {
                                    setSheetState(() {
                                      selected = product;
                                      if (nameController.text.trim().isEmpty) {
                                        nameController.text =
                                            _shortProductName(product.name);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: Text(tr.text('cancel')),
                          ),
                        ),
                        if (page.slots[slotIndex].productId != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(
                                  sheetContext, const _QuickProductSlot()),
                              child: Text(tr.text('delete')),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected == null
                                ? null
                                : () => Navigator.pop(
                                      sheetContext,
                                      _QuickProductSlot(
                                        productId: selected!.id,
                                        shortName: nameController.text
                                                .trim()
                                                .isEmpty
                                            ? _shortProductName(selected!.name)
                                            : nameController.text.trim(),
                                      ),
                                    ),
                            child: Text(tr.text('save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    nameController.dispose();
    if (result == null) return;
    setState(() => page.slots[slotIndex] = result);
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  Widget _buildMobileSalesLayout(BuildContext context, AppLocalizations tr,
      List<Product> products, double pagePadding) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pagePadding),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSaleShiftStatusCard(context, tr),
                  const SizedBox(height: 8),
                  _buildMobileSaleControls(context, tr, products),
                  const SizedBox(height: 8),
                  _buildCart(context, tr,
                      compactActions: true,
                      showTotals: false,
                      showActions: false,
                      expandCartList: false),
                ],
              ),
            ),
          ),
          Padding(
            padding:
                EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, pagePadding),
            child: _buildMobileInvoiceSummary(context, tr),
          ),
        ],
      ),
    );
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
            _buildBarcodeStation(context, tr,
                products: products, embedded: true),
            if (_scannerActive) ...[
              const SizedBox(height: 10),
              _buildEmbeddedScannerPreview(),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runAlignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _MobileSaleAction(
                    icon: Icons.search,
                    label: tr.text('search'),
                    onTap: () => _showProductSearchSheet(products)),
                _MobileSaleAction(
                    icon: Icons.grid_view_rounded,
                    label: tr.text('quick_products'),
                    onTap: () => _showQuickProductsSheet(products)),
                _MobileSaleAction(
                    icon: Icons.point_of_sale_outlined,
                    label: 'الوردية',
                    onTap: _showSaleShiftQuickAction),
                _MobileSaleAction(
                    icon: Icons.receipt_long_outlined,
                    label: tr.text('recent_invoices'),
                    onTap: _showInvoicesSheet),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileInvoiceSummary(BuildContext context, AppLocalizations tr) {
    return _buildSaleTotalBar(context, tr, compact: true);
  }

  Widget _buildSaleTotalBar(BuildContext context, AppLocalizations tr,
      {bool compact = false}) {
    final totalText =
        formatUsdReferenceAmount(_total, widget.store.storeProfile);
    final hasDiscount = _discount > 0;
    final content = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(
                          '${_formatQuantity(_itemsCount)} ${tr.text('items_count')}',
                          style: Theme.of(context).textTheme.bodyMedium)),
                  Text(totalText,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              if (hasDiscount) ...[
                const SizedBox(height: 4),
                Text(
                    '${tr.text('discount')}: ${formatUsdReferenceAmount(_discount, widget.store.storeProfile)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _cart.isEmpty
                    ? null
                    : () => _openPaymentPage(printAfterSave: false),
                icon: const Icon(Icons.payments_outlined),
                label: Text(tr.text('continue_payment')),
              ),
            ],
          )
        : Row(
            children: [
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
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    if (hasDiscount)
                      Text(
                          '${tr.text('discount')}: ${formatUsdReferenceAmount(_discount, widget.store.storeProfile)}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _cart.isEmpty
                    ? null
                    : () => _openPaymentPage(printAfterSave: false),
                icon: const Icon(Icons.payments_outlined),
                label: Text(tr.text('continue_payment')),
              ),
            ],
          );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18, vertical: compact ? 12 : 14),
        child: content,
      ),
    );
  }

  void _toggleManualBarcodeInput() {
    setState(() => _manualBarcodeInput = !_manualBarcodeInput);
    if (_manualBarcodeInput) {
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _barcodeFocusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  void _restoreScannerMode() {
    if (_manualBarcodeInput) {
      setState(() => _manualBarcodeInput = false);
    }
    _barcodeFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _loadHeldSaleCarts() async {
    final raw = LocalDatabaseService.getString(_heldSalesStorageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final carts = decoded
          .map((item) =>
              _HeldSaleCart.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((cart) => cart.items.isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _heldCarts
          ..clear()
          ..addAll(carts);
      });
    } catch (_) {
      // Ignore malformed local drafts rather than blocking the sales page.
    }
  }

  Future<void> _saveHeldSaleCarts() async {
    await LocalDatabaseService.setString(_heldSalesStorageKey,
        jsonEncode(_heldCarts.map((cart) => cart.toJson()).toList()));
  }

  String _defaultHeldCartName() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return 'Hold ${_heldCarts.length + 1} - $hour:$minute';
  }

  Future<void> _holdCurrentCart() async {
    if (_cart.isEmpty) return;
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController(text: _defaultHeldCartName());
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('hold_cart')),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: tr.text('hold_cart_name')),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(nameController.text),
              child: Text(tr.text('hold'))),
        ],
      ),
    );
    nameController.dispose();
    if (name == null) return;

    final trimmedName =
        name.trim().isEmpty ? _defaultHeldCartName() : name.trim();
    final cart = _HeldSaleCart(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmedName,
      createdAt: DateTime.now(),
      items: _cart.map(_HeldSaleItem.fromDraft).toList(),
    );
    setState(() {
      _heldCarts.insert(0, cart);
      _cart.clear();
      _selectedCartIndex = null;
      _pendingDeleteCartIndex = null;
    });
    await _saveHeldSaleCarts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('cart_held_successfully'))));
    _restoreScannerMode();
  }

  Future<void> _restoreHeldCart(_HeldSaleCart heldCart) async {
    if (_cart.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('hold_current_cart_first'))));
      return;
    }
    final restored = <_DraftSaleItem>[];
    final missingNames = <String>[];
    for (final item in heldCart.items) {
      Product? product;
      for (final candidate in widget.store.products) {
        if (candidate.id == item.productId &&
            candidate.isActive &&
            !candidate.isDeleted) {
          product = candidate;
          break;
        }
      }
      if (product == null) {
        missingNames.add(item.productName);
        continue;
      }
      ProductSaleUnit? saleUnit;
      for (final unit in product.effectiveSaleUnits) {
        if (unit.id == item.saleUnitId) {
          saleUnit = unit;
          break;
        }
      }
      final restoredUnit = saleUnit ?? item.saleUnit;
      restored.add(_DraftSaleItem(
          product: product,
          quantity: item.quantity,
          saleUnit: restoredUnit.copyWith(
            price: widget.store
                .defaultProductUsdPrice(product, unitId: restoredUnit.id),
          )));
    }
    if (restored.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('held_cart_products_missing'))));
      return;
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(restored);
      _selectedCartIndex = _cart.isEmpty ? null : 0;
      _pendingDeleteCartIndex = null;
      _heldCarts.removeWhere((cart) => cart.id == heldCart.id);
    });
    await _saveHeldSaleCarts();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    final tr = AppLocalizations.of(context);
    final message = missingNames.isEmpty
        ? tr.text('cart_restored_successfully')
        : '${tr.text('cart_restored_with_missing_products')}: ${missingNames.join(', ')}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _restoreScannerMode();
  }

  Future<void> _deleteHeldCart(_HeldSaleCart heldCart) async {
    setState(() => _heldCarts.removeWhere((cart) => cart.id == heldCart.id));
    await _saveHeldSaleCarts();
  }

  Future<void> _showHeldCartsDialog() async {
    final tr = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${tr.text('held_carts')} (${_heldCarts.length})'),
          content: SizedBox(
            width: 420,
            child: _heldCarts.isEmpty
                ? Text(tr.text('no_held_carts'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _heldCarts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cart = _heldCarts[index];
                      return ListTile(
                        leading: const Icon(Icons.pause_circle_outline),
                        title: Text(cart.name),
                        subtitle: Text(
                            '${cart.items.length} ${tr.text('items')} • ${_formatHeldCartTime(cart.createdAt)}'),
                        trailing: IconButton(
                          tooltip: tr.text('delete'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _deleteHeldCart(cart);
                            setDialogState(() {});
                          },
                        ),
                        onTap: () => _restoreHeldCart(cart),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr.text('close'))),
          ],
        ),
      ),
    );
  }

  String _formatHeldCartTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  bool get _canUseCameraScanner =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _scanBarcodeWithCamera() async {
    if (_scannerActive) {
      await _scannerController.stop();
      if (mounted) setState(() => _scannerActive = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _scannerActive = true;
      _scannerStartFailed = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _startEmbeddedScanner());
  }

  Future<void> _startEmbeddedScanner() async {
    if (!mounted || !_scannerActive) return;
    setState(() => _scannerStartFailed = false);
    try {
      await _scannerController.start();
    } catch (_) {
      if (mounted) setState(() => _scannerStartFailed = true);
    }
  }

  void _handleEmbeddedBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now();
      if (_lastScannedCode == code &&
          _lastScannedAt != null &&
          now.difference(_lastScannedAt!) <
              const Duration(milliseconds: 1500)) {
        return;
      }
      _lastScannedCode = code;
      _lastScannedAt = now;
      _barcodeController.text = code;
      _addByCode(code);
      return;
    }
  }

  Widget _buildEmbeddedScannerPreview() {
    if (!_canUseCameraScanner || !_scannerActive) {
      return const SizedBox.shrink();
    }
    final tr = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scannerHeight = VentioResponsive.adaptiveWidth(
      context,
      mobile: 132,
      tablet: 150,
      desktop: 170,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.center_focus_strong_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr.text('inline_barcode_scanner'),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: tr.text('stop_camera_scanner'),
                  onPressed: _scanBarcodeWithCamera,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Container(
            height: scannerHeight,
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  fit: BoxFit.cover,
                  onDetect: _handleEmbeddedBarcode,
                  errorBuilder: (context, error) => _EmbeddedScannerError(
                    onRetry: _startEmbeddedScanner,
                  ),
                  placeholderBuilder: (_) =>
                      ColoredBox(color: scheme.surfaceContainerHighest),
                ),
                if (_scannerStartFailed)
                  _EmbeddedScannerError(onRetry: _startEmbeddedScanner),
                IgnorePointer(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final frameWidth = VentioResponsive.clampToScreen(
                          context,
                          constraints.maxWidth * 0.62,
                          min: 150,
                          horizontalPadding: 48,
                        );
                        return Container(
                          width: frameWidth,
                          height: (frameWidth * 0.40).clamp(64, 90).toDouble(),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeStation(BuildContext context, AppLocalizations tr,
      {required List<Product> products, bool embedded = false}) {
    return Container(
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.45),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final field = TextField(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            autofocus: false,
            readOnly: false,
            showCursor: _manualBarcodeInput,
            enableInteractiveSelection: _manualBarcodeInput,
            // Keep TextInputType.text in both modes so a physical keyboard / USB
            // barcode scanner can type into the field even when the touch
            // keyboard is intentionally hidden in scanner mode.
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onTap: () {
              if (!_manualBarcodeInput) {
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }
            },
            decoration: InputDecoration(
              labelText: tr.text('scan_barcode'),
              hintText: tr.text('scan_barcode_hint'),
              prefixIcon: const Icon(Icons.qr_code_2),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _manualBarcodeInput
                        ? tr.text('hide_keyboard')
                        : tr.text('manual_input'),
                    onPressed: _toggleManualBarcodeInput,
                    icon: Icon(_manualBarcodeInput
                        ? Icons.keyboard_hide_outlined
                        : Icons.keyboard_outlined),
                  ),
                  IconButton(
                    tooltip: tr.text('search_product'),
                    onPressed: () => _showProductSearchSheet(products),
                    icon: const Icon(Icons.search),
                  ),
                  if (_canUseCameraScanner)
                    IconButton(
                      tooltip: _scannerActive
                          ? tr.text('stop_camera_scanner')
                          : tr.text('start_camera_scanner'),
                      onPressed: _scanBarcodeWithCamera,
                      icon: Icon(_scannerActive
                          ? Icons.videocam_off_outlined
                          : Icons.camera_alt_outlined),
                    ),
                  IconButton(
                    tooltip: tr.text('clear'),
                    onPressed: () {
                      _barcodeController.clear();
                      if (_manualBarcodeInput) {
                        _barcodeFocusNode.requestFocus();
                      } else {
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      }
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ),
            onSubmitted: _addByCode,
          );
          final button = FilledButton.icon(
              onPressed: () => _addByCode(_barcodeController.text),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(tr.text('add_to_cart')));
          final preview = embedded
              ? const SizedBox.shrink()
              : _buildEmbeddedScannerPreview();
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 8),
                button,
                if (!embedded && _scannerActive) preview,
              ],
            );
          }
          return Column(
            children: [
              Row(children: [
                const Icon(Icons.qr_code_scanner, size: 32),
                const SizedBox(width: 12),
                Expanded(child: field),
                const SizedBox(width: 12),
                button
              ]),
              if (!embedded && _scannerActive) preview,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCart(
    BuildContext context,
    AppLocalizations tr, {
    bool compactActions = false,
    bool showTotals = true,
    bool showActions = true,
    bool expandCartList = true,
  }) {
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
            builder: (context, constraints) {
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: tr.text('decrease_qty'),
                    onPressed: () => _decreaseOrMarkCartItem(index),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                      width: 42,
                      child: Text(_formatQuantity(item.quantity),
                          textAlign: TextAlign.center)),
                  IconButton(
                    tooltip: tr.text('increase_qty'),
                    onPressed: () =>
                        _changeCartQuantity(index, item.quantity + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    tooltip: tr.text('delete'),
                    onPressed: () => _removeCartItem(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              );
              if (constraints.maxWidth < 520) {
                return InkWell(
                  onTap: () {
                    _selectCartIndex(index);
                    _showQuantitySheet(index);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: rowColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.needsAutoCorrection) ...[
                              Icon(Icons.warning_amber_rounded,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer),
                              const SizedBox(width: 6),
                            ],
                            if (isPendingDelete) ...[
                              Icon(Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                                child: Text(item.product.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '${item.product.code} • ${formatUsdReferenceAmount(item.unitPrice, widget.store.storeProfile)} • ${_formatQuantity(item.quantity)} ${item.unitName} • ${_stockAvailabilityLabel(item.product, tr, includeUnit: true)}'),
                        Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions),
                      ],
                    ),
                  ),
                );
              }
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                tileColor: rowColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: item.needsAutoCorrection || isPendingDelete
                    ? Icon(
                        isPendingDelete
                            ? Icons.delete_sweep_outlined
                            : Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      )
                    : null,
                title: Text(item.product.name),
                subtitle: Text(
                    '${item.product.code} • ${formatUsdReferenceAmount(item.unitPrice, widget.store.storeProfile)} • ${_formatQuantity(item.quantity)} ${item.unitName} • ${_stockAvailabilityLabel(item.product, tr, includeUnit: true)}'),
                onTap: () {
                  _selectCartIndex(index);
                  _showQuantitySheet(index);
                },
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: VentioResponsive.adaptiveWidth(context,
                          mobile: 144, tablet: 164, desktop: 178)),
                  child: actions,
                ),
              );
            },
          );
        },
      );
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
        physics: expandCartList ? null : const NeverScrollableScrollPhysics(),
      );
      cartContent = expandCartList ? Expanded(child: list) : list;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      onPressed: _confirmClearCart,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(tr.text('clear_cart'))),
                if (_cart.isNotEmpty)
                  TextButton.icon(
                      onPressed: _holdCurrentCart,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: Text(tr.text('hold'))),
                if (_heldCarts.isNotEmpty)
                  TextButton.icon(
                      onPressed: _showHeldCartsDialog,
                      icon:
                          const Icon(Icons.playlist_add_check_circle_outlined),
                      label:
                          Text('${tr.text('restore')} (${_heldCarts.length})')),
              ],
            ),
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
                  child: Text(
                    tr.text('discount_exceeds_subtotal'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              _totalLine(tr.text('total'),
                  _formatSaleCurrency(_invoiceTotal, _invoiceCurrency),
                  isBold: true),
            ],
            if (showActions) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final primary = FilledButton.icon(
                      onPressed: _cart.isEmpty
                          ? null
                          : () => _openPaymentPage(printAfterSave: true),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(tr.text('continue_payment')));
                  final secondary = OutlinedButton.icon(
                      onPressed: _cart.isEmpty
                          ? null
                          : () => _openPaymentPage(printAfterSave: false),
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
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalLine(String title, String value, {bool isBold = false}) {
    final style = isBold
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(title), Text(value, style: style)],
      ),
    );
  }

  Future<void> _showInvoicesSheet() async {
    final tr = AppLocalizations.of(context);
    final sales = widget.store.sales;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.85,
          child: _buildInvoicesPanel(sheetContext, tr, sales),
        );
      },
    );
  }

  Widget _buildInvoicesPanel(
      BuildContext context, AppLocalizations tr, List<Sale> sales) {
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.text('recent_invoices'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: sales.isEmpty
                  ? EmptyStateCard(
                      icon: Icons.receipt_long_outlined,
                      title: tr.text('no_sales'),
                      subtitle: tr.text('no_sales_desc'))
                  : ListView.separated(
                      itemCount: sales.length > 50 ? 50 : sales.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sale = sales[index];
                        return ExpansionTile(
                          leading: Icon(sale.isCancelled
                              ? Icons.cancel_outlined
                              : Icons.check_circle),
                          title: Text(sale.invoiceNo),
                          subtitle: Text(
                              '${sale.customerName} • ${sale.date.toLocal()}'
                                  .split('.')
                                  .first),
                          trailing: Text(sale.isCancelled
                              ? sale.status
                              : formatUsdReferenceAmount(
                                  sale.total, widget.store.storeProfile)),
                          children: [
                            ...sale.items.map(
                              (item) => ListTile(
                                dense: true,
                                title: Text(item.productName),
                                subtitle: Text(
                                    '${tr.text('quantity')}: ${_formatQuantity(item.quantity)} ${item.unitName} × ${formatUsdReferenceAmount(item.unitPrice, widget.store.storeProfile)}'),
                                trailing: Text(formatUsdReferenceAmount(
                                    item.lineTotal, widget.store.storeProfile)),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _handleInvoiceAction(() =>
                                        InvoicePdfService.printInvoice(
                                            sale: sale,
                                            profile: widget.store.storeProfile,
                                            locale: AppLocalizations.of(context)
                                                .locale)),
                                    icon: const Icon(Icons.print_outlined),
                                    label: Text(tr.text('print_invoice')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _handleInvoiceAction(() =>
                                        InvoicePdfService.shareInvoice(
                                            sale: sale,
                                            profile: widget.store.storeProfile,
                                            locale: AppLocalizations.of(context)
                                                .locale)),
                                    icon: const Icon(Icons.share_outlined),
                                    label: Text(tr.text('share_pdf')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: (!sale.isCancelled &&
                                            widget.store.deliveryNoteForSale(
                                                    sale.id) ==
                                                null)
                                        ? () =>
                                            _createDeliveryNote(context, sale)
                                        : null,
                                    icon: const Icon(
                                        Icons.local_shipping_outlined),
                                    label: Text(tr.text('delivery_note')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: (!sale.isCancelled &&
                                            widget.store.canDeleteOrCancel)
                                        ? () => _returnSale(context, sale)
                                        : null,
                                    icon: const Icon(
                                        Icons.assignment_return_outlined),
                                    label: Text(tr.text('return_sale')),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeCartQuantity(int index, double quantity) {
    if (index < 0 || index >= _cart.length) return;
    final item = _cart[index];
    final minQuantity = item.product.allowsDecimalQuantity ? 0.001 : 1.0;
    final rounded = item.product.allowsDecimalQuantity
        ? quantity
        : quantity.roundToDouble();
    final cleanQuantity = rounded < minQuantity ? minQuantity : rounded;
    final willNeedCorrection = item.product.trackStock &&
        cleanQuantity * item.conversionToBase > item.product.stock;
    setState(() {
      _cart[index] = item.copyWith(quantity: cleanQuantity);
      _selectedCartIndex = index;
      _pendingDeleteCartIndex = null;
    });
    if (willNeedCorrection) {
      unawaited(BarcodeFeedbackService.playError(force: true));
    }
  }

  Future<void> _showQuantitySheet(int index) async {
    if (index < 0 || index >= _cart.length) return;
    final tr = AppLocalizations.of(context);
    final item = _cart[index];
    final controller =
        TextEditingController(text: _formatQuantity(item.quantity));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.product.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: item.product.allowsDecimalQuantity
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                      : [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: tr.text('quantity')),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final current =
                              double.tryParse(controller.text) ?? item.quantity;
                          controller.text = _formatQuantity(
                              (current - 1) < 1 ? 1 : (current - 1));
                          controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length));
                        },
                        icon: const Icon(Icons.remove),
                        label: Text(tr.text('decrease_qty')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final current =
                              double.tryParse(controller.text) ?? item.quantity;
                          controller.text = _formatQuantity(
                              (current + 1) < 1 ? 1 : (current + 1));
                          controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length));
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tr.text('increase_qty')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    final quantity =
                        double.tryParse(controller.text) ?? item.quantity;
                    Navigator.pop(sheetContext);
                    _changeCartQuantity(index, quantity);
                    FocusScope.of(context).unfocus();
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  void _showQuickProductsSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    _ensureQuickPages(products, tr);
    var sheetSelectedPageIndex =
        _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          _ensureQuickPages(products, tr);
          sheetSelectedPageIndex =
              sheetSelectedPageIndex.clamp(0, _quickPages.length - 1).toInt();
          final page = _quickPages[sheetSelectedPageIndex];
          final visibleSlotIndexes = _quickVisibleSlotIndexes(page);

          Future<bool> closeSheet() async {
            final navigator = Navigator.of(sheetContext);
            final canClose = await _confirmCloseQuickGridEditor();
            if (canClose && navigator.canPop()) navigator.pop();
            return canClose;
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              unawaited(closeSheet());
            },
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * 0.82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(tr.text('quick_product_grid'),
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          IconButton(
                            tooltip: tr.text('close'),
                            onPressed: () {
                              unawaited(closeSheet());
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 42,
                              child: _quickGridEditMode
                                  ? ReorderableListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      buildDefaultDragHandles: false,
                                      itemCount: _quickPages.length,
                                      onReorderItem: (oldIndex, newIndex) {
                                        _moveQuickPage(oldIndex, newIndex);
                                        setModalState(() =>
                                            sheetSelectedPageIndex =
                                                _selectedQuickPageIndex);
                                      },
                                      proxyDecorator: (child, _, __) =>
                                          Material(
                                              elevation: 6,
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              child: child),
                                      itemBuilder: (context, index) {
                                        final selected =
                                            index == sheetSelectedPageIndex;
                                        return Padding(
                                          key: ValueKey(
                                              'mobile_quick_page_${index}_${_quickPages[index].name}'),
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
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                            maxWidth: 120),
                                                    child: Text(
                                                        _quickPages[index].name,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                      Icons.edit_outlined,
                                                      size: 16),
                                                ],
                                              ),
                                              selected: selected,
                                              onSelected: (_) async {
                                                if (selected) {
                                                  await _renameQuickPage(index);
                                                  setModalState(() {});
                                                } else {
                                                  setState(() =>
                                                      _selectedQuickPageIndex =
                                                          index);
                                                  setModalState(() =>
                                                      sheetSelectedPageIndex =
                                                          index);
                                                }
                                              },
                                              deleteIcon: _quickPages.length > 1
                                                  ? const Icon(Icons.close,
                                                      size: 18)
                                                  : null,
                                              onDeleted: _quickPages.length > 1
                                                  ? () {
                                                      _deleteQuickPage(index);
                                                      setModalState(() =>
                                                          sheetSelectedPageIndex =
                                                              _selectedQuickPageIndex);
                                                    }
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _quickPages.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (context, index) {
                                        final selected =
                                            index == sheetSelectedPageIndex;
                                        return InputChip(
                                          label: Text(_quickPages[index].name),
                                          selected: selected,
                                          onSelected: (_) {
                                            setState(() =>
                                                _selectedQuickPageIndex =
                                                    index);
                                            setModalState(() =>
                                                sheetSelectedPageIndex = index);
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ),
                          if (_quickGridEditMode) ...[
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: Text(tr.text('page')),
                              onPressed: () {
                                _addQuickPage();
                                setModalState(() => sheetSelectedPageIndex =
                                    _selectedQuickPageIndex);
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_quickGridEditMode)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _cancelQuickGridEditing();
                                  setModalState(() => sheetSelectedPageIndex =
                                      _selectedQuickPageIndex);
                                },
                                icon: const Icon(Icons.close),
                                label: Text(tr.text('cancel')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  _saveQuickGridEditing();
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.check),
                                label: Text(tr.text('save')),
                              ),
                            ),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () {
                            _startQuickGridEditing();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(tr.text('edit_layout')),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleSlotIndexes.isEmpty
                            ? Center(child: Text(tr.text('no_products')))
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount =
                                      constraints.maxWidth > 520 ? 3 : 2;
                                  return GridView.builder(
                                    itemCount: visibleSlotIndexes.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 1.18,
                                    ),
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
                                          isEmpty,
                                          onChanged: () =>
                                              setModalState(() {}));
                                      if (!_quickGridEditMode) return child;
                                      final target = DragTarget<int>(
                                        onWillAcceptWithDetails: (details) =>
                                            details.data != slotIndex,
                                        onAcceptWithDetails: (details) {
                                          _moveQuickSlot(
                                              details.data, slotIndex);
                                          setModalState(() {});
                                        },
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
                                                  width: 2),
                                            ),
                                            child: child,
                                          );
                                        },
                                      );
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
                                              child: child),
                                        ),
                                        childWhenDragging: Opacity(
                                            opacity: 0.35, child: child),
                                        child: target,
                                      );
                                    },
                                  );
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
  }

  Future<String?> _scanCodeWithCameraOnce() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    final trimmed = code?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showProductSearchSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: _search);
    var query = _search;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final filteredProducts = products.where((product) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return product.name.toLowerCase().contains(q) ||
                product.code.toLowerCase().contains(q) ||
                product.barcode.toLowerCase().contains(q) ||
                product.effectiveSaleUnits
                    .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
                product.effectivePurchaseUnits
                    .any((unit) => unit.barcode.toLowerCase().contains(q)) ||
                product.category.toLowerCase().contains(q);
          }).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr.text('search_product'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: tr.text('search_product'),
                        suffixIcon: IconButton(
                          tooltip: tr.text('scan_with_camera'),
                          onPressed: () async {
                            final code = await _scanCodeWithCameraOnce();
                            if (code == null) return;
                            controller.text = code;
                            setModalState(() => query = code);
                          },
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                      ),
                      onChanged: (value) => setModalState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? Center(child: Text(tr.text('no_products')))
                          : ListView.separated(
                              itemCount: filteredProducts.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                return ListTile(
                                  title: Text(product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${product.code} • ${_stockAvailabilityLabel(product, tr)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: Text(formatUsdReferenceAmount(
                                      widget.store
                                          .defaultProductUsdPrice(product),
                                      widget.store.storeProfile)),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _search = '';
                                    _searchController.clear();
                                    FocusScope.of(context).unfocus();
                                    _addProduct(product);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  String _saleSaveFailureMessage(BuildContext context, Object error) {
    final tr = AppLocalizations.of(context);

    if (error is StateError) {
      final raw = error.message.trim();
      if (raw.isNotEmpty) {
        return localizeRuntimeMessage(raw, tr);
      }
    }

    if (error is ArgumentError) {
      final raw = (error.message ?? '').toString().trim();
      if (raw.isNotEmpty &&
          (raw.contains('وردية') ||
              raw.contains('درج') ||
              raw.toLowerCase().contains('cash drawer') ||
              raw.toLowerCase().contains('device'))) {
        return localizeRuntimeMessage(raw, tr);
      }
      return tr.text('sale_validation_failed');
    }

    final raw = error.toString().trim();
    final normalized = raw
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Invalid argument\(s\):\s*'), '')
        .trim();
    if (normalized.isNotEmpty &&
        (normalized.contains('وردية') ||
            normalized.contains('درج') ||
            normalized.toLowerCase().contains('cash drawer') ||
            normalized.toLowerCase().contains('device'))) {
      return localizeRuntimeMessage(normalized, tr);
    }

    return tr.text('sale_validation_failed');
  }

  Future<void> _showTemporarySaleDebugDialog({
    required BuildContext context,
    required Object error,
    required StackTrace stackTrace,
    required String userMessage,
  }) async {
    final tr = AppLocalizations.of(context);
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer()
      ..writeln('VENTIO TEMP SALE DEBUG')
      ..writeln('time: $now')
      ..writeln('screen: sales_page')
      ..writeln('action: confirm_payment -> createSale')
      ..writeln('user_message: $userMessage')
      ..writeln('error_type: ${error.runtimeType}')
      ..writeln('error: $error')
      ..writeln('device_id: ${widget.store.deviceId}')
      ..writeln('payment_method: $_paymentMethod')
      ..writeln('payment_status: $_derivedPaymentStatus')
      ..writeln('invoice_currency: $_invoiceCurrency')
      ..writeln('payment_currency: $_paymentCurrency')
      ..writeln('subtotal: $_subtotal')
      ..writeln('discount: $_discount')
      ..writeln('raw_total: $_rawInvoiceTotal')
      ..writeln(
          'cash_rounding_difference: $_cashRoundingDifferenceInInvoiceCurrency')
      ..writeln('total: $_invoiceTotal')
      ..writeln(
          'cash_received: ${_showsCashReceived ? _cashReceivedAmount : (_isCashPayment ? _invoiceTotal : 0.0)}')
      ..writeln('paid_amount: $_derivedPaidAmount')
      ..writeln('selected_customer_id: $_selectedCustomerId')
      ..writeln('cart_items: ${_cart.length}');

    for (var i = 0; i < _cart.length; i += 1) {
      final item = _cart[i];
      buffer
        ..writeln('item[$i].product_id: ${item.product.id}')
        ..writeln('item[$i].name: ${item.product.name}')
        ..writeln('item[$i].code: ${item.product.code}')
        ..writeln('item[$i].quantity: ${item.quantity}')
        ..writeln('item[$i].unit_name: ${item.unitName}')
        ..writeln('item[$i].base_quantity: ${item.baseQuantity}')
        ..writeln('item[$i].conversion_to_base: ${item.conversionToBase}')
        ..writeln('item[$i].stock: ${item.product.stock}')
        ..writeln('item[$i].needs_auto_correction: ${item.needsAutoCorrection}')
        ..writeln('item[$i].unit_price: ${item.unitPrice}')
        ..writeln('item[$i].unit_cost: ${item.product.usdCost}');
    }

    buffer
      ..writeln('stack_trace:')
      ..writeln(stackTrace.toString());

    final debugText = buffer.toString();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تفاصيل خطأ حفظ الفاتورة'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  userMessage,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'هذه رسالة تتبع مؤقتة. انسخها وأرسلها للمراجعة لمعرفة أين يفشل الحفظ بالضبط.',
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 360),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      debugText,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr.text('close')),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: debugText));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('تم نسخ تفاصيل الخطأ')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDeliveryNote(BuildContext context, Sale sale) async {
    final tr = AppLocalizations.of(context);
    try {
      await widget.store.createDeliveryNoteFromSale(sale.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('delivery_note_created'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _returnSale(BuildContext context, Sale sale) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('return_sale')),
        content: Text(tr
            .text('return_sale_confirm')
            .replaceAll('{invoice}', sale.invoiceNo)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr.text('confirm_return_sale'))),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.store.returnSale(sale.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('sale_returned_stock_restored'))));
    }
  }

  _BarcodeAddResult _addProduct(Product product,
      {ProductSaleUnit? saleUnit, bool showBarcodeFeedback = false}) {
    if (!widget.store.canSell) {
      if (showBarcodeFeedback) {
        _showBarcodeAddFeedback(_BarcodeAddResult.notAllowed);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)
                .text('role_not_allowed_to_sell'))));
      }
      _restoreScannerMode();
      return _BarcodeAddResult.notAllowed;
    }

    final rawSelectedUnit = saleUnit ?? product.effectiveSaleUnits.first;
    final selectedUnit = rawSelectedUnit.copyWith(
      price: widget.store
          .defaultProductUsdPrice(product, unitId: rawSelectedUnit.id),
    );

    final existingIndex = _cart.indexWhere((item) =>
        item.product.id == product.id &&
        item.unitName ==
            (selectedUnit.name.trim().isNotEmpty
                ? selectedUnit.name
                : product.unit));
    var result = _BarcodeAddResult.added;
    setState(() {
      if (existingIndex == -1) {
        _cart.insert(
            0,
            _DraftSaleItem(
                product: product, quantity: 1, saleUnit: selectedUnit));
      } else {
        _cart[existingIndex] = _cart[existingIndex]
            .copyWith(quantity: _cart[existingIndex].quantity + 1);
      }
      _selectedCartIndex = existingIndex == -1 ? 0 : existingIndex;
      _pendingDeleteCartIndex = null;
      final cartItem = _cart[_selectedCartIndex!];
      if (cartItem.needsAutoCorrection) {
        result = _BarcodeAddResult.autoCorrected;
      }
    });

    if (showBarcodeFeedback) {
      _showBarcodeAddFeedback(result);
    } else if (result == _BarcodeAddResult.autoCorrected) {
      unawaited(BarcodeFeedbackService.playError(force: true));
    }

    _restoreScannerMode();
    return result;
  }

  _BarcodeAddResult _addByCode(String code) {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      _restoreScannerMode();
      return _BarcodeAddResult.empty;
    }

    Product? product;
    ProductSaleUnit? saleUnit;
    for (final candidate
        in widget.store.products.where((item) => !item.isDeleted)) {
      final matchedUnit = candidate.unitForBarcode(cleanCode);
      if (candidate.code.trim().toLowerCase() == cleanCode.toLowerCase() ||
          matchedUnit != null) {
        product = candidate;
        saleUnit = matchedUnit ?? candidate.effectiveSaleUnits.first;
        break;
      }
    }
    if (product == null) {
      _barcodeController.clear();
      _showBarcodeAddFeedback(_BarcodeAddResult.notFound);
      _restoreScannerMode();
      return _BarcodeAddResult.notFound;
    }

    _barcodeController.clear();
    return _addProduct(product, saleUnit: saleUnit, showBarcodeFeedback: true);
  }

  void _showBarcodeAddFeedback(_BarcodeAddResult result) {
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (result) {
      case _BarcodeAddResult.added:
        unawaited(BarcodeFeedbackService.play(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_product_added'))));
        return;
      case _BarcodeAddResult.autoCorrected:
        unawaited(BarcodeFeedbackService.playError(force: true));
        return;
      case _BarcodeAddResult.notFound:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_product_not_registered'))));
        return;
      case _BarcodeAddResult.outOfStock:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_out_of_stock'))));
        return;
      case _BarcodeAddResult.stockLimitReached:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('barcode_stock_limit_reached'))));
        return;
      case _BarcodeAddResult.notAllowed:
        unawaited(BarcodeFeedbackService.playError(force: true));
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('role_not_allowed_to_sell'))));
        return;
      case _BarcodeAddResult.empty:
        return;
    }
  }

  Future<void> _openPaymentPage({required bool printAfterSave}) async {
    if (_cart.isEmpty) return;
    _invoiceCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
    _discountCurrency = _invoiceCurrency;
    _paymentCurrency = widget.store.storeProfile.defaultSalePaymentCurrency;
    _paymentExchangeRateController.text =
        widget.store.storeProfile.usdToLbpRate.toStringAsFixed(0);
    if (_paymentMethod == 'Cash') {
      _paidAmountController.clear();
    } else if (_paidAmountController.text.trim().isEmpty) {
      _paidAmountController.text = '0';
    }

    final originalMethod = _paymentMethod;
    final originalPaymentCurrency = _paymentCurrency;
    final originalCash = _paidAmountController.text;
    final originalCustomerId = _selectedCustomerId;
    final originalDiscount = _discountController.text;
    final originalDiscountCurrency = _discountCurrency;

    BuildContext? activePaymentDialogContext;
    StateSetter? activePaymentDialogSetState;
    bool handlePaymentHardwareShortcut(KeyEvent event) {
      final dialogContext = activePaymentDialogContext;
      final setDialogState = activePaymentDialogSetState;
      if (dialogContext == null ||
          setDialogState == null ||
          ModalRoute.of(dialogContext)?.isCurrent != true) {
        return false;
      }
      return _handlePaymentShortcutKey(event, dialogContext, setDialogState);
    }

    HardwareKeyboard.instance.addHandler(handlePaymentHardwareShortcut);
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            activePaymentDialogContext = dialogContext;
            activePaymentDialogSetState = setDialogState;
            final pageTr = AppLocalizations.of(context);
            final invoiceTotal = _invoiceTotal;
            final cashInInvoice = _cashReceivedAmount;
            final paidInInvoice = _derivedPaidAmount;
            final remaining = (invoiceTotal - paidInInvoice)
                .clamp(0, double.infinity)
                .toDouble();
            final nonCashOrCredit = (invoiceTotal - cashInInvoice)
                .clamp(0, double.infinity)
                .toDouble();
            return Focus(
              focusNode: _paymentShortcutFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) => _handlePaymentShortcutKey(
                      event, dialogContext, setDialogState)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
              child: AlertDialog(
                title: Text(pageTr.text('payment_page')),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPaymentShortcutGuide(context, pageTr),
                        const SizedBox(height: 8),
                        _buildCustomerSelector(context, pageTr,
                            modalSetState: setDialogState),
                        const SizedBox(height: 16),
                        _buildPaymentMethodChips(pageTr,
                            modalSetState: setDialogState),
                        const SizedBox(height: 16),
                        _buildPaymentCurrencySwitch(pageTr,
                            modalSetState: setDialogState),
                        if (_showsCashReceived) ...[
                          const SizedBox(height: 16),
                          _buildCashReceivedField(pageTr,
                              modalSetState: setDialogState),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          focusNode: _discountFocusNode,
                          controller: _discountController,
                          decoration: InputDecoration(
                              labelText: pageTr.text('discount')),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}$'))
                          ],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) {
                            setState(
                                () => _discountCurrency = _invoiceCurrency);
                            setDialogState(() {});
                          },
                        ),
                        const Divider(height: 28),
                        _totalLine(pageTr.text('total'),
                            _formatSaleCurrency(invoiceTotal, _invoiceCurrency),
                            isBold: true),
                        if (_showsCashReceived)
                          _totalLine(
                              pageTr.text('cash_received_amount'),
                              _formatSaleCurrency(
                                  cashInInvoice, _invoiceCurrency)),
                        if (_isCreditPayment)
                          _totalLine(pageTr.text('remaining_debt'),
                              _formatSaleCurrency(remaining, _invoiceCurrency),
                              isBold: true)
                        else if (!_isCashPayment)
                          _totalLine(
                              pageTr.text('non_cash_amount'),
                              _formatSaleCurrency(
                                  nonCashOrCredit, _invoiceCurrency),
                              isBold: true)
                        else
                          _totalLine(
                              pageTr.text('paid_amount'),
                              _formatSaleCurrency(
                                  invoiceTotal, _invoiceCurrency),
                              isBold: true),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(pageTr.text('cancel'))),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(pageTr.text('confirm_payment')),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      HardwareKeyboard.instance.removeHandler(handlePaymentHardwareShortcut);
      activePaymentDialogContext = null;
      activePaymentDialogSetState = null;
    }

    if (confirmed == true) {
      await _saveCurrentInvoice(printAfterSave: printAfterSave);
    } else if (mounted) {
      setState(() {
        _paymentMethod = originalMethod;
        _paymentCurrency = originalPaymentCurrency;
        _paidAmountController.text = originalCash;
        _selectedCustomerId = originalCustomerId;
        _discountController.text = originalDiscount;
        _discountCurrency = originalDiscountCurrency;
      });
    }
  }

  Future<void> _saveCurrentInvoice({required bool printAfterSave}) async {
    if (_cart.isEmpty) return;
    if (_discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('discount_exceeds_subtotal'))));
      return;
    }

    if (_isWalkInCustomer && _paymentMethod == 'Credit') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('walk_in_cash_only'))));
      return;
    }

    final cashReceivedAmount = _showsCashReceived
        ? _cashReceivedAmount
        : (_isCashPayment ? _invoiceTotal : 0.0);
    if (_showsCashReceived && cashReceivedAmount > _invoiceTotal) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('invalid_cash_received_amount'))));
      return;
    }
    final paidAmount = _derivedPaidAmount;
    final paymentStatus = _derivedPaymentStatus;

    late final Sale sale;
    try {
      sale = await widget.store.createSale(
        customerName: widget.store.resolveCustomerName(_selectedCustomerId),
        customerId: _selectedCustomerId,
        discount: _discount,
        originalDiscount: double.tryParse(_discountController.text.trim()) ?? 0,
        discountCurrency: _discountCurrency,
        discountExchangeRateAtEntry: exchangeRate(
          widget.store.storeProfile.baseCurrency,
          _discountCurrency,
          widget.store.storeProfile,
          effectiveAt: DateTime.now(),
        ),
        paymentMethod: _paymentMethod,
        paymentStatus: paymentStatus,
        invoiceCurrency: _invoiceCurrency,
        paymentCurrency: _paymentCurrency,
        exchangeRateAtPayment: _saleExchangeRate,
        paidAmount: paidAmount,
        cashReceivedAmount: cashReceivedAmount,
        paidAmountInPaymentCurrency: _isCreditPayment
            ? _cashReceivedInPaymentCurrency
            : _convertCurrencyAmount(
                paidAmount, _invoiceCurrency, _paymentCurrency),
        cashReceivedAmountInPaymentCurrency: _isCashPayment
            ? _convertCurrencyAmount(
                cashReceivedAmount, _invoiceCurrency, _paymentCurrency)
            : _cashReceivedInPaymentCurrency,
        items: _cart
            .map(
              (item) => SaleItem(
                productId: item.product.id,
                productName: item.product.name,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                unitName: item.unitName,
                baseQuantity: item.baseQuantity,
                conversionToBase: item.conversionToBase,
                unitCost: 0,
              ),
            )
            .toList(),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = _saleSaveFailureMessage(context, error);
      await _showTemporarySaleDebugDialog(
        context: context,
        error: error,
        stackTrace: stackTrace,
        userMessage: message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;

    setState(() {
      _cart.clear();
      _selectedCartIndex = null;
      _pendingDeleteCartIndex = null;
      _discountController.clear();
      _paidAmountController.clear();
      _selectedCustomerId = AppStore.walkInCustomerId;
      _paymentMethod = 'Cash';
      _invoiceCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
      _paymentCurrency = widget.store.storeProfile.defaultSalePaymentCurrency;
      _discountCurrency = widget.store.storeProfile.defaultSaleInvoiceCurrency;
      _paymentExchangeRateController.text =
          widget.store.storeProfile.usdToLbpRate.toStringAsFixed(0);
      _searchController.clear();
      _barcodeController.clear();
      _search = '';
    });
    _restoreScannerMode();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)
            .text('invoice_created_successfully'))));

    if (printAfterSave) {
      await _handleInvoiceAction(() => InvoicePdfService.printInvoice(
          sale: sale,
          profile: widget.store.storeProfile,
          locale: AppLocalizations.of(context).locale));
    }
  }

  Future<void> _handleInvoiceAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('pdf_action_failed'))));
    }
  }
}

class _EmbeddedScannerError extends StatelessWidget {
  const _EmbeddedScannerError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 24),
              const SizedBox(height: 8),
              Text(
                tr.text('camera_scanner_error'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr.text('retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleShiftStatus {
  const _SaleShiftStatus({
    required this.drawer,
    required this.openSession,
    required this.drawers,
    required this.cashLocations,
    required this.branchId,
  });

  final AdvancedAccountingItem? drawer;
  final AdvancedAccountingItem? openSession;
  final List<AdvancedAccountingItem> drawers;
  final List<AdvancedAccountingItem> cashLocations;
  final String branchId;
}

class _MobileSaleAction extends StatelessWidget {
  const _MobileSaleAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _QuickProductSlot {
  const _QuickProductSlot({this.productId, this.shortName});

  final String? productId;
  final String? shortName;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'shortName': shortName,
      };

  factory _QuickProductSlot.fromJson(Map<String, dynamic> json) =>
      _QuickProductSlot(
        productId: json['productId'] as String?,
        shortName: json['shortName'] as String?,
      );
}

class _QuickProductPage {
  _QuickProductPage({required this.name, required this.slots});

  String name;
  final List<_QuickProductSlot> slots;

  Map<String, dynamic> toJson() => {
        'name': name,
        'slots': slots.map((slot) => slot.toJson()).toList(),
      };

  factory _QuickProductPage.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'];
    final slots = rawSlots is List
        ? rawSlots
            .whereType<Map<String, dynamic>>()
            .map(_QuickProductSlot.fromJson)
            .toList()
        : <_QuickProductSlot>[];
    while (slots.length < 12) {
      slots.add(const _QuickProductSlot());
    }
    if (slots.length > 12) slots.removeRange(12, slots.length);
    return _QuickProductPage(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Favorites',
      slots: slots,
    );
  }
}

String _formatQuantity(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  var text = value.toStringAsFixed(3);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

class _HeldSaleCart {
  const _HeldSaleCart(
      {required this.id,
      required this.name,
      required this.createdAt,
      required this.items});

  final String id;
  final String name;
  final DateTime createdAt;
  final List<_HeldSaleItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory _HeldSaleCart.fromJson(Map<String, dynamic> json) => _HeldSaleCart(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Hold',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) =>
                _HeldSaleItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((item) => item.quantity > 0 && item.productId.isNotEmpty)
            .toList(),
      );
}

class _HeldSaleItem {
  const _HeldSaleItem(
      {required this.productId,
      required this.productName,
      required this.quantity,
      required this.saleUnitId,
      required this.saleUnit});

  final String productId;
  final String productName;
  final double quantity;
  final String saleUnitId;
  final ProductSaleUnit saleUnit;

  factory _HeldSaleItem.fromDraft(_DraftSaleItem item) => _HeldSaleItem(
        productId: item.product.id,
        productName: item.product.name,
        quantity: item.quantity,
        saleUnitId: item.saleUnit.id,
        saleUnit: item.saleUnit,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'saleUnitId': saleUnitId,
        'saleUnit': saleUnit.toJson(),
      };

  factory _HeldSaleItem.fromJson(Map<String, dynamic> json) => _HeldSaleItem(
        productId: json['productId'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        saleUnitId: json['saleUnitId'] as String? ?? 'base',
        saleUnit: ProductSaleUnit.fromJson(
            Map<String, dynamic>.from(json['saleUnit'] as Map? ?? const {})),
      );
}

class _DraftSaleItem {
  const _DraftSaleItem(
      {required this.product,
      required this.quantity,
      ProductSaleUnit? saleUnit})
      : saleUnit = saleUnit ??
            const ProductSaleUnit(
                id: 'base',
                name: '',
                conversionToBase: 1,
                price: 0,
                isDefault: true);

  final Product product;
  final double quantity;
  final ProductSaleUnit saleUnit;

  double get unitPrice => saleUnit.price > 0 ? saleUnit.price : product.price;
  double get conversionToBase =>
      saleUnit.conversionToBase <= 0 ? 1 : saleUnit.conversionToBase;
  double get baseQuantity => quantity * conversionToBase;
  String get unitName =>
      saleUnit.name.trim().isNotEmpty ? saleUnit.name : product.unit;
  double get lineTotal => quantity * unitPrice;
  bool get needsAutoCorrection =>
      product.trackStock && baseQuantity > product.stock;

  _DraftSaleItem copyWith(
      {Product? product, double? quantity, ProductSaleUnit? saleUnit}) {
    return _DraftSaleItem(
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
        saleUnit: saleUnit ?? this.saleUnit);
  }
}
