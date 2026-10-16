import 'domain/sale_cart.dart';
import 'domain/sale_cart_item.dart';
import 'domain/sale_payment_preview.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/revision_cache.dart';
import 'package:ventio/core/contracts/application_session.dart';
import '../../models/app_user.dart';
import '../../models/customer.dart';
import '../../models/credit_note.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/sale_summary.dart';
import '../../models/user_role.dart';
import '../../models/warehouse.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/shortcut_key_picker.dart';
import '../barcode/barcode_scanner_page.dart';
import '../security/sensitive_action_guard.dart';

part 'sales_page_cart_panel.dart';
part 'sales_page_credit_notes_returns.dart';
part 'sales_page_customer_shift.dart';
part 'sales_page_desktop_layout.dart';
part 'sales_page_held_carts_scanner.dart';
part 'sales_page_invoice_workflows.dart';
part 'sales_page_mobile_layout.dart';
part 'sales_page_posted_sale_edit.dart';
part 'sales_page_product_data.dart';
part 'sales_page_product_dialogs.dart';
part 'sales_page_quick_products.dart';
part 'sales_page_sale_payment.dart';
part 'sales_page_sale_return_save.dart';
part 'sales_page_shift_dialogs.dart';
part 'sales_page_shortcuts_cart.dart';
part 'sales_page_models.dart';
part 'sales_page_widgets.dart';

enum _BarcodeAddResult {
  added,
  autoCorrected,
  empty,
  notAllowed,
  notFound,
  outOfStock,
  stockLimitReached
}

enum _SalesExitChoice { clearCart, holdCart, cancel }

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.store, this.onExitGuardChanged});
  final ApplicationSession store;
  final ValueChanged<Future<bool> Function()?>? onExitGuardChanged;
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final TextEditingController _searchController = TextEditingController();

  final TextEditingController _barcodeController = TextEditingController();

  final TextEditingController _discountController = TextEditingController();

  final TextEditingController _discountPercentController =
      TextEditingController();

  final TextEditingController _paidAmountController = TextEditingController();

  final TextEditingController _paymentExchangeRateController =
      TextEditingController();

  final TextEditingController _invoiceSearchController =
      TextEditingController();

  final FocusNode _barcodeFocusNode = FocusNode();

  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'sale_shortcuts');

  final FocusNode _paymentShortcutFocusNode =
      FocusNode(debugLabel: 'sale_payment_shortcuts');

  final FocusNode _discountFocusNode =
      FocusNode(debugLabel: 'sale_payment_discount');

  final FocusNode _cashReceivedFocusNode =
      FocusNode(debugLabel: 'sale_payment_cash_received');

  final ScrollController _cartScrollController = ScrollController();

  final Map<int, GlobalKey> _cartItemKeys = <int, GlobalKey>{};

  static const String _quickPagesStorageKey = 'sale_quick_product_pages_v1';

  static const String _quickTileSizeStorageKey =
      'sale_quick_product_tile_size_v1';

  static const String _quickPanelFractionStorageKey =
      'sale_quick_product_panel_fraction_v1';

  static const String _heldSalesStorageKey = 'sale_held_carts_v1';

  final SaleCart _saleCart = SaleCart();
  List<SaleCartItem> get _cart => _saleCart.items;

  final List<_QuickProductPage> _quickPages = [];

  String _selectedCustomerId = CommerceDefaults.walkInCustomerId;

  String _selectedWarehouseId = Warehouse.defaultId;

  String _paymentMethod = 'Cash';

  String _invoiceCurrency = 'USD';

  String _salePriceType = 'retail';

  String _paymentCurrency = 'USD';

  String _discountCurrency = 'USD';

  String _search = '';

  final List<_HeldSaleCart> _heldCarts = [];

  final MobileScannerController _scannerController = MobileScannerController(
      autoStart: false,
      cameraResolution: const Size(1280, 720),
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500);

  bool _scannerActive = false;

  bool _scannerStartFailed = false;

  bool _exitPromptOpen = false;

  bool _manualBarcodeInput = false;

  bool _showInvoiceProfit = false;

  double? _invoicePreviewBatchCostTotal;

  bool _quickGridEditMode = false;

  _QuickProductTileSize _quickTileSize = _QuickProductTileSize.medium;

  double _quickPanelFraction = 0.4;

  List<_QuickProductPage>? _quickPagesEditSnapshot;

  int _selectedQuickPageIndex = 0;

  int _visibleInvoiceCount = 50;

  Future<_SalesQueryResult?>? _salesQueryFuture;

  String _salesQueryFutureKey = '';

  Future<List<Product>?>? _visibleProductsFuture;

  String _visibleProductsFutureKey = '';

  final Map<String, Future<Sale?>> _invoiceDetailsFutureById =
      <String, Future<Sale?>>{};

  final Set<String> _expandedInvoiceIds = <String>{};

  bool Function(KeyEvent)? _activeProductSearchKeyHandler;

  FocusNode? _activeProductSearchFocusNode;

  String? _lastScannedCode;

  DateTime? _lastScannedAt;

  int _cashShiftRefreshKey = 0;

  bool _refreshingProductData = false;

  int? _selectedCartIndex;

  int? _pendingDeleteCartIndex;

  final RevisionKeyCache<List<Product>> _visibleProductsCache =
      RevisionKeyCache<List<Product>>();

  final RevisionKeyCache<List<Product>> _activeProductsCache =
      RevisionKeyCache<List<Product>>();

  final RevisionKeyCache<Map<String, String>> _productSearchIndexCache =
      RevisionKeyCache<Map<String, String>>();

  final RevisionValueCache<Map<String, _BarcodeProductMatch>>
      _barcodeLookupCache =
      RevisionValueCache<Map<String, _BarcodeProductMatch>>();

  final RevisionKeyCache<Map<String, String>> _invoiceSearchIndexCache =
      RevisionKeyCache<Map<String, String>>();

  Timer? _productSearchRevealTimer;

  int _storeUiRevision = 0;

  late Future<void> _dataFuture;

  @override
  void initState() {
    super.initState();
    widget.onExitGuardChanged?.call(_confirmSalesExit);
    widget.store.addListener(_handleStoreChanged);
    _selectedCustomerId = CommerceDefaults.walkInCustomerId;
    _invoiceCurrency = widget.store.runtime.profile.defaultSaleInvoiceCurrency;
    _paymentCurrency = widget.store.runtime.profile.defaultSalePaymentCurrency;
    _discountCurrency = widget.store.runtime.profile.defaultSaleInvoiceCurrency;
    _selectedWarehouseId = widget.store.inventory
        .resolveWarehouseForSale(
            warehouseId: widget.store.inventory.saleWarehouseId)
        .id;
    _paymentExchangeRateController.text =
        widget.store.runtime.profile.usdToLbpRate.toStringAsFixed(0);
    _storeUiRevision = _currentStoreUiRevision();
    _loadQuickProductPreferences();
    _loadQuickProductPages();
    _loadHeldSaleCarts();
    _dataFuture = widget.store.commerce.ensureSalesLoaded();
    _dataFuture.then((_) {
      if (!mounted) return;
      setState(() {
        _selectedWarehouseId = widget.store.inventory
            .resolveWarehouseForSale(
                warehouseId: widget.store.inventory.saleWarehouseId)
            .id;
      });
    });
    HardwareKeyboard.instance.addHandler(_handleSaleHardwareShortcutKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _manualBarcodeInput) return;
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  @override
  void didUpdateWidget(covariant SalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onExitGuardChanged != widget.onExitGuardChanged) {
      oldWidget.onExitGuardChanged?.call(null);
      widget.onExitGuardChanged?.call(_confirmSalesExit);
    }
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _visibleProductsCache.invalidate();
      _activeProductsCache.invalidate();
      _productSearchIndexCache.invalidate();
      _barcodeLookupCache.invalidate();
      _invoiceSearchIndexCache.invalidate();
      _salesQueryFuture = null;
      _salesQueryFutureKey = '';
      _visibleProductsFuture = null;
      _visibleProductsFutureKey = '';
      _visibleInvoiceCount = 50;
      _invoiceSearchController.clear();
      _invoiceDetailsFutureById.clear();
      _expandedInvoiceIds.clear();
      _resetProductSearchReveal();
      _dataFuture = widget.store.commerce.ensureSalesLoaded();
      _dataFuture.then((_) {
        if (!mounted) return;
        setState(() {
          _selectedWarehouseId = widget.store.inventory
              .resolveWarehouseForSale(
                  warehouseId: widget.store.inventory.saleWarehouseId)
              .id;
        });
      });
      _storeUiRevision = _currentStoreUiRevision();
    }
  }

  @override
  void dispose() {
    widget.onExitGuardChanged?.call(null);
    _activeProductSearchKeyHandler = null;
    _activeProductSearchFocusNode = null;
    widget.store.removeListener(_handleStoreChanged);
    HardwareKeyboard.instance.removeHandler(_handleSaleHardwareShortcutKey);
    _productSearchRevealTimer?.cancel();
    _searchController.dispose();
    _barcodeController.dispose();
    _discountController.dispose();
    _discountPercentController.dispose();
    _paidAmountController.dispose();
    _paymentExchangeRateController.dispose();
    _invoiceSearchController.dispose();
    _barcodeFocusNode.dispose();
    _shortcutFocusNode.dispose();
    _paymentShortcutFocusNode.dispose();
    _discountFocusNode.dispose();
    _cashReceivedFocusNode.dispose();
    _cartScrollController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.canViewSales) {
      return _AccessDeniedScaffold(
          title: tr.text('sales_page'),
          message: tr.text('no_access_sales_data'));
    }
    return PopScope(
        canPop: _cart.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || _cart.isEmpty) return;
          final navigator = Navigator.of(context);
          unawaited(_confirmSalesExit().then((canLeave) {
            if (!canLeave || !mounted) return;
            navigator.maybePop();
          }));
        },
        child: FutureBuilder<void>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator.adaptive());
              }
              return FutureBuilder<List<Product>?>(
                  future: _visibleProductsFromSqlite(),
                  builder: (context, productSnapshot) {
                    final products = productSnapshot.data ?? _visibleProducts();
                    return Focus(
                        focusNode: _shortcutFocusNode,
                        autofocus: true,
                        child: LayoutBuilder(builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 980;
                          final pagePadding =
                              VentioResponsive.pagePadding(context);
                          if (!isWide) {
                            return _buildMobileSalesLayout(
                                context, tr, products, pagePadding);
                          }
                          return _buildDesktopSalesLayout(
                              context, tr, products, pagePadding);
                        }));
                  });
            }));
  }
}

String _formatMoneyInput(double value) {
  if (!value.isFinite) return '0';
  var text = value.toStringAsFixed(4);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
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
