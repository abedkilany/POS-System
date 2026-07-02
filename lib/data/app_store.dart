import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/local_database_service.dart';
import '../core/services/accounting_service.dart';
import '../core/services/account_auth_service.dart';
import '../core/services/app_logging_service.dart';
import '../core/services/startup_timing_service.dart';
import '../core/services/sync_diagnostics_log.dart';
import '../core/sync_unified/sync_device_state.dart';
import '../core/snapshot/unified_snapshot.dart';
import '../core/utils/currency_utils.dart';

import '../models/account_transaction.dart';
import '../models/catalog_item.dart';
import '../models/customer.dart';
import '../models/delivery_note.dart';
import '../models/manufacturing.dart';
import '../models/expense.dart';
import '../models/inventory_count.dart';
import '../models/product.dart';
import '../models/product_pricing.dart';
import '../models/product_costing.dart';
import '../models/inventory_cost_layer.dart';
import '../models/purchase.dart';
import '../models/purchase_item.dart';
import '../models/supplier_purchase_price.dart';
import '../models/supplier_product_price.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/sale_quotation.dart';
import '../models/store_profile.dart';
import '../models/supplier.dart';
import '../models/sync_change.dart';
import '../models/sync_queue_item.dart';
import '../models/user_role.dart';
import '../models/app_user.dart';
import '../models/app_identity.dart';

part 'app_store_backup.dart';

bool _verifyPasswordInBackground(Map<String, String> request) {
  const prefix = 'pbkdf2sha256:';
  final password = request['password'] ?? '';
  final storedHash = request['storedHash'] ?? '';
  if (!storedHash.startsWith(prefix)) return false;
  final parts = storedHash.split(':');
  if (parts.length != 4) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 100000) return false;
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  derivator.init(
    pc.Pbkdf2Parameters(base64Url.decode(parts[2]), iterations, 32),
  );
  final hash = derivator.process(
    Uint8List.fromList(utf8.encode('ventio|password|$password')),
  );
  return storedHash ==
      '$prefix$iterations:${parts[2]}:${base64UrlEncode(hash)}';
}

String _hashPasswordInBackground(Map<String, String> request) {
  const prefix = 'pbkdf2sha256:';
  final password = request['password'] ?? '';
  final salt = request['salt'] ?? '';
  final iterations = int.tryParse(request['iterations'] ?? '') ?? 210000;
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
  final hash = derivator.process(
    Uint8List.fromList(utf8.encode('ventio|password|$password')),
  );
  return '$prefix$iterations:$salt:${base64UrlEncode(hash)}';
}

List<Map<String, dynamic>> _decodeJsonListPayload(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) return const <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
}

class DataConflict {
  const DataConflict({
    required this.entityType,
    required this.keyName,
    required this.keyValue,
    required this.recordIds,
    this.blocking = false,
    this.message = '',
  });

  final String entityType;
  final String keyName;
  final String keyValue;
  final List<String> recordIds;
  final bool blocking;
  final String message;

  String get title => '$entityType duplicate $keyName: $keyValue';
}

class BusinessDataIntegrityResult {
  const BusinessDataIntegrityResult({
    required this.ok,
    required this.message,
    this.problemCount = 0,
  });
  final bool ok;
  final String message;
  final int problemCount;
}

class PurchasesOverview {
  const PurchasesOverview({
    required this.totalCount,
    required this.totalPurchasesAmount,
    required this.monthlyTotal,
    required this.monthlyCount,
    required this.draftTotal,
    required this.draftCount,
    required this.receivedCount,
    required this.returnedCount,
    required this.cancelledCount,
    required this.pendingPurchaseCount,
  });

  final int totalCount;
  final double totalPurchasesAmount;
  final double monthlyTotal;
  final int monthlyCount;
  final double draftTotal;
  final int draftCount;
  final int receivedCount;
  final int returnedCount;
  final int cancelledCount;
  final int pendingPurchaseCount;
}

class ExpensesOverview {
  const ExpensesOverview({
    required this.totalCount,
    required this.totalExpensesAmount,
    required this.draftCount,
    required this.postedCount,
    required this.cancelledCount,
    required this.categoryCount,
  });

  final int totalCount;
  final double totalExpensesAmount;
  final int draftCount;
  final int postedCount;
  final int cancelledCount;
  final int categoryCount;
}

class _ProductPurchaseMetrics {
  const _ProductPurchaseMetrics({
    this.lastCost,
    this.averageCost = 0,
    this.supplierCount = 0,
  });

  final double? lastCost;
  final double averageCost;
  final int supplierCount;
}

class AppStoreActionException implements Exception {
  const AppStoreActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef AppStoreTraceSink = void Function(
  String section,
  String phase,
  int elapsedMs,
  Map<String, Object?> metadata,
);

class AppStore extends ChangeNotifier {
  static AppStoreTraceSink? _traceSink;

  static void setTraceSink(AppStoreTraceSink? sink) {
    _traceSink = sink;
  }

  void _emitTrace(
    String section,
    String phase,
    Stopwatch sw,
    Map<String, Object?> metadata,
  ) {
    final sink = _traceSink;
    if (sink == null) return;
    sink(section, phase, sw.elapsedMilliseconds, metadata);
  }

  Future<T> _traceAsync<T>(
    String section,
    String phase,
    Future<T> Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
      return result;
    } catch (_) {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
      rethrow;
    }
  }

  void _traceSync(
    String section,
    String phase,
    void Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final sw = Stopwatch()..start();
    try {
      action();
    } finally {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
    }
  }

  T _traceSyncResult<T>(
    String section,
    String phase,
    T Function() action, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final sw = Stopwatch()..start();
    try {
      return action();
    } finally {
      sw.stop();
      _emitTrace(section, phase, sw, metadata);
    }
  }

  static const String walkInCustomerId = 'walk_in';
  static const String walkInCustomerName = 'Walk-in Customer';

  static const _productsKey = 'products_v4';
  static const _customersKey = 'customers_v4';
  static const _salesKey = 'sales_v4';
  static const _saleQuotationsKey = 'sale_quotations_v1';
  static const _deliveryNotesKey = 'delivery_notes_v1';
  static const _billsOfMaterialsKey = 'bills_of_materials_v1';
  static const _manufacturingOrdersKey = 'manufacturing_orders_v1';
  static const _suppliersKey = 'suppliers_v4';
  static const _supplierProductPricesKey = 'supplier_product_prices_v1';
  static const _priceListsKey = 'price_lists_v1';
  static const _productPricesKey = 'product_prices_v1';
  static const _productPriceOverridesKey = 'product_price_overrides_v1';
  static const _productCostsKey = 'product_costs_v1';
  static const _costingMethodHistoryKey = 'costing_method_history_v1';
  static const _inventoryCostingMethodKey = 'inventory_costing_method_v1';
  static const _inventoryCostLayersKey = 'inventory_cost_layers_v1';
  static const _expensesKey = 'expenses_v4';
  static const _purchasesKey = 'purchases_v1';
  static const _stockMovementsKey = 'stock_movements_v1';
  static const _inventoryCountsKey = 'inventory_counts_v1';
  static const _warehousesKey = 'warehouses_v1';
  static const _accountTransactionsKey = 'account_transactions_v1';
  static const _purchaseCounterKey = 'purchase_counter_v1';
  static const _storeProfileKey = 'store_profile_v5';
  static const _categoriesKey = 'product_categories_v1';
  static const _brandsKey = 'product_brands_v1';
  static const _unitsKey = 'product_units_v1';
  static const _invoiceCounterKey = 'invoice_counter_v1';
  static const _deviceIdKey = 'sync_device_id_v1';
  static const _syncChangesKey = 'sync_changes_v1';
  static const _syncQueueKey = 'sync_queue_v1';
  static const _syncSequenceKey = 'sync_sequence_v1';
  static const _schemaVersionKey = 'schema_version_v1';
  static const _legacyLocalCredentialHashPrefix = 'sha256salt:';
  static const _passwordHashPrefix = 'pbkdf2sha256:';
  static const _passwordHashIterations = 210000;
  static const _currentRoleKey =
      'current_role_v1'; // legacy, no longer user-editable
  static const _rolesKey = 'roles_v1';
  static const _usersKey = 'users_v1';
  static const _activeUserKey = 'active_user_v1';
  static const _rememberLoginKey = 'remember_login_v1';
  static const _appIdentityKey = 'app_identity_v1';
  static const _themeModeKey = 'theme_mode_v1';
  static const _localeKey = 'locale_v1';
  static const _hostTransferApprovedDeviceKey =
      'host_transfer_approved_device_v1';
  static const _hostTransferRequestKey = 'host_transfer_request_v1';
  static const _hostTransferNotificationKey = 'host_transfer_notification_v1';
  static const _devFeatureFlagsKey = 'dev_feature_flags_v1';
  static const _stressLabEnabledFlag = 'stressLabEnabled';

  final List<Product> _products = [];
  final List<Customer> _customers = [];
  final List<Sale> _sales = [];
  final List<SaleQuotation> _saleQuotations = [];
  final List<DeliveryNote> _deliveryNotes = [];
  final List<BillOfMaterials> _billsOfMaterials = [];
  final List<ManufacturingOrder> _manufacturingOrders = [];
  final List<Supplier> _suppliers = [];
  final List<SupplierProductPrice> _supplierProductPrices = [];
  final List<PriceList> _priceLists = [];
  final List<ProductPrice> _productPrices = [];
  final List<ProductPriceOverride> _productPriceOverrides = [];
  final List<ProductCost> _productCosts = [];
  final List<CostingMethodHistory> _costingMethodHistory = [];
  final List<InventoryCostLayer> _inventoryCostLayers = [];
  final List<CatalogItem> _categories = [];
  final List<CatalogItem> _brands = [];
  final List<CatalogItem> _units = [];
  final List<Expense> _expenses = [];
  final List<Purchase> _purchases = [];
  final List<StockMovement> _stockMovements = [];
  final List<InventoryCountSession> _inventoryCounts = [];
  final List<Warehouse> _warehouses = [];
  final List<AccountTransaction> _accountTransactions = [];
  final Map<String, int> _purchaseIndexById = <String, int>{};
  final Map<String, int> _stockMovementIndexById = <String, int>{};
  final Map<String, int> _expenseIndexById = <String, int>{};
  final Map<String, int> _accountTransactionIndexById = <String, int>{};
  final Map<String, int> _productIndexById = <String, int>{};
  final Map<String, String> _productIdByNormalizedCode = <String, String>{};
  final Map<String, String> _productIdByNormalizedBarcode = <String, String>{};
  final Map<String, int> _customerIndexById = <String, int>{};
  final Map<String, String> _customerIdByNormalizedName = <String, String>{};
  final Map<String, int> _supplierIndexById = <String, int>{};
  final Map<String, String> _supplierIdByNormalizedName = <String, String>{};
  final Map<String, ProductPrice> _productPriceByLookupKey =
      <String, ProductPrice>{};
  final Map<String, ProductCost> _productCostByProductId =
      <String, ProductCost>{};
  final Map<String, int> _productCostIndexByProductId = <String, int>{};
  final Map<String, int> _inventoryCostLayerIndexById = <String, int>{};
  final Map<String, double> _accountBalanceCache = <String, double>{};
  final Map<String, List<AccountTransaction>>
      _accountTransactionsByAccountCache = <String, List<AccountTransaction>>{};
  bool _accountLedgerCacheDirty = true;
  final Map<String, Map<String, double>> _warehouseStockByProductCache =
      <String, Map<String, double>>{};
  bool _warehouseStockCacheDirty = true;
  final Map<String, List<SupplierPurchasePrice>>
      _purchaseHistoryByProductCache = <String, List<SupplierPurchasePrice>>{};
  final Map<String, _ProductPurchaseMetrics> _purchaseMetricsByProductCache =
      <String, _ProductPurchaseMetrics>{};
  bool _purchaseInsightsCacheDirty = true;
  List<Product>? _cachedProducts;
  int _cachedProductsGeneration = -1;
  List<Product>? _cachedStockTrackedProducts;
  int _cachedStockTrackedProductsGeneration = -1;
  UnmodifiableListView<Sale>? _cachedSales;
  int _cachedSalesGeneration = -1;
  final List<SyncChange> _syncChanges = [];
  final List<SyncQueueItem> _syncQueue = [];
  final List<SyncChange> _sqliteDirtySyncChanges = [];
  int _storeRevision = 0;
  int _productsRevision = 0;
  int _customersRevision = 0;
  int _salesRevision = 0;
  int _deliveryNotesRevision = 0;
  int _suppliersRevision = 0;
  int _supplierProductPricesRevision = 0;
  int _purchasesRevision = 0;
  int _expensesRevision = 0;
  int _stockMovementsRevision = 0;
  int _inventoryCountsRevision = 0;
  int _warehousesRevision = 0;
  int _accountTransactionsRevision = 0;
  int _storeProfileRevision = 0;
  final List<SyncQueueItem> _sqliteDirtySyncQueue = [];
  final Map<String, Map<String, Map<String, dynamic>>>
      _sqliteDirtyBusinessRows = <String, Map<String, Map<String, dynamic>>>{};
  StoreProfile _storeProfile = StoreProfile.defaults;
  InventoryCostingMethod _inventoryCostingMethod =
      InventoryCostingMethod.weightedAverage;
  int _invoiceCounter = 0;
  int _purchaseCounter = 0;
  String _currentRole = 'admin'; // legacy compatibility
  String _deviceId = '';
  final List<UserRole> _roles = [];
  final List<AppUser> _users = [];
  AppUser? _activeUser;
  bool _rememberLogin = false;
  AppIdentity? _appIdentity;
  int _syncSequence = 0;
  bool _productDerivedDataDirty = false;
  Timer? _productDerivedDataFlushTimer;
  Future<void>? _productDerivedDataFlushInFlight;
  final Map<String, Future<void>> _pendingSaleAccountingTasks =
      <String, Future<void>>{};
  final Map<String, Future<void>> _pendingPurchaseAccountingTasks =
      <String, Future<void>>{};
  final Map<String, Future<void>> _pendingExpenseAccountingTasks =
      <String, Future<void>>{};
  UnmodifiableListView<SaleQuotation>? _cachedSaleQuotations;
  UnmodifiableListView<DeliveryNote>? _cachedDeliveryNotes;
  Map<String, DeliveryNote>? _cachedDeliveryNoteBySaleId;
  UnmodifiableListView<BillOfMaterials>? _cachedBillsOfMaterials;
  UnmodifiableListView<ManufacturingOrder>? _cachedManufacturingOrders;
  UnmodifiableListView<Supplier>? _cachedSuppliers;
  UnmodifiableListView<SupplierProductPrice>? _cachedSupplierProductPrices;
  UnmodifiableListView<PriceList>? _cachedPriceLists;
  UnmodifiableListView<ProductPrice>? _cachedProductPrices;
  UnmodifiableListView<ProductPriceOverride>? _cachedProductPriceOverrides;
  UnmodifiableListView<ProductCost>? _cachedProductCosts;
  UnmodifiableListView<CostingMethodHistory>? _cachedCostingMethodHistory;
  UnmodifiableListView<InventoryCostLayer>? _cachedInventoryCostLayers;
  PurchasesOverview? _cachedPurchasesOverview;
  int _cachedPurchasesOverviewRevision = -1;
  String _cachedPurchasesOverviewMonthKey = '';
  ExpensesOverview? _cachedExpensesOverview;
  int _cachedExpensesOverviewRevision = -1;
  int _derivedListCacheGeneration = 0;
  int _cachedSaleQuotationsGeneration = -1;
  int _cachedDeliveryNotesGeneration = -1;
  int _cachedDeliveryNoteBySaleIdGeneration = -1;
  int _cachedBillsOfMaterialsGeneration = -1;
  int _cachedManufacturingOrdersGeneration = -1;
  int _cachedSuppliersGeneration = -1;
  int _cachedSupplierProductPricesGeneration = -1;
  int _cachedPriceListsGeneration = -1;
  int _cachedProductPricesGeneration = -1;
  int _cachedProductPriceOverridesGeneration = -1;
  int _cachedProductCostsGeneration = -1;
  int _cachedCostingMethodHistoryGeneration = -1;
  int _cachedInventoryCostLayersGeneration = -1;

  Customer get walkInCustomer => Customer(
        id: walkInCustomerId,
        name: walkInCustomerName,
        phone: '',
        address: '',
      );

  bool _isReady = false;
  bool _heavyDataLoadCompleted = false;
  bool _ledgerDataLoadCompleted = false;
  Future<void>? _ledgerDataLoadFuture;
  bool _syncDataLoadCompleted = false;
  Future<void>? _syncDataLoadFuture;
  final Map<String, Future<void>> _deferredGroupLoadFutures =
      <String, Future<void>>{};
  final Set<String> _deferredGroupLoadCompleted = <String>{};

  bool get isReady => _isReady;
  int get productsRevision => _productsRevision;
  int get customersRevision => _customersRevision;
  int get salesRevision => _salesRevision;
  int get deliveryNotesRevision => _deliveryNotesRevision;
  int get suppliersRevision => _suppliersRevision;
  int get supplierProductPricesRevision => _supplierProductPricesRevision;
  int get purchasesRevision => _purchasesRevision;
  int get expensesRevision => _expensesRevision;
  int get stockMovementsRevision => _stockMovementsRevision;
  int get inventoryCountsRevision => _inventoryCountsRevision;
  int get warehousesRevision => _warehousesRevision;
  int get accountTransactionsRevision => _accountTransactionsRevision;
  int get storeProfileRevision => _storeProfileRevision;
  int get accountingRevision => Object.hashAll(<Object?>[
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);
  int get dashboardRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
        _syncSequence,
      ]);
  int get reportsRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);
  int get inventoryRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _stockMovementsRevision,
        _inventoryCountsRevision,
        _warehousesRevision,
      ]);
  int get salesPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _salesRevision,
        _deliveryNotesRevision,
        _storeProfileRevision,
      ]);
  int get productsPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _purchasesRevision,
        _storeProfileRevision,
      ]);
  bool get isCoreDataLoaded => _isReady;
  bool get isLedgerDataLoaded => _isReady;
  bool get isSyncDataLoaded => _syncDataLoadCompleted;
  bool get isHeavyDataLoaded =>
      _heavyDataLoadCompleted &&
      _ledgerDataLoadCompleted &&
      _syncDataLoadCompleted;

  Future<void> warmDeferredPageCaches() async {
    await StartupTimingService.measure(
      'app_store.post_startup_cache_warm',
      () async {
        await ensureHeavyDataLoaded();
      },
      category: 'app_store',
    );
  }

  Future<void> _requestLedgerDataLoad() {
    if (_ledgerDataLoadCompleted) return Future.value();
    final existing = _ledgerDataLoadFuture;
    if (existing != null) return existing;
    final future = ensureAccountTransactionsLoaded();
    _ledgerDataLoadFuture = future.whenComplete(() {
      _ledgerDataLoadFuture = null;
      _ledgerDataLoadCompleted = true;
    });
    return _ledgerDataLoadFuture!;
  }

  Future<void> _requestSyncDataLoad() {
    if (_syncDataLoadCompleted) return Future.value();
    final existing = _syncDataLoadFuture;
    if (existing != null) return existing;
    final future = _loadSyncDeferredStartupData();
    _syncDataLoadFuture = future.whenComplete(() {
      _syncDataLoadFuture = null;
      _syncDataLoadCompleted = true;
    });
    return _syncDataLoadFuture!;
  }

  Future<void> _loadDeferredGroup<T>({
    required String key,
    required Future<List<T>> Function() loader,
    required List<T> target,
    void Function()? afterLoad,
  }) {
    return _requestDeferredGroupLoad(key, () async {
      final items = await loader();
      target
        ..clear()
        ..addAll(items);
      afterLoad?.call();
      notifyListeners();
    });
  }

  Future<void> _requestDeferredGroupLoad(
    String key,
    Future<void> Function() action,
  ) {
    if (_deferredGroupLoadCompleted.contains(key)) {
      return Future.value();
    }
    final existing = _deferredGroupLoadFutures[key];
    if (existing != null) return existing;
    final future = action().catchError((error, stackTrace) {
      debugPrint('Deferred group load failed for $key: $error');
      debugPrint('$stackTrace');
    }).whenComplete(() {
      _deferredGroupLoadFutures.remove(key);
      _deferredGroupLoadCompleted.add(key);
    });
    _deferredGroupLoadFutures[key] = future;
    return future;
  }

  Future<void> ensureProductsLoaded() => _loadDeferredGroup<Product>(
        key: _productsKey,
        loader: _loadProductsForStartup,
        target: _products,
        afterLoad: () {
          _ensureCatalogDefaults();
          _rebuildProductIndexes();
          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          _ensureCostingMethodHistory();
          _touchDataRevisions(products: true);
        },
      );

  Future<void> ensureCustomersLoaded() => _loadDeferredGroup<Customer>(
        key: _customersKey,
        loader: _loadCustomersForStartup,
        target: _customers,
        afterLoad: () {
          _normalizeCustomers();
          _rebuildCustomerIndexes();
          _touchDataRevisions(customers: true);
        },
      );

  Future<void> ensureSalesLoaded() => _loadDeferredGroup<Sale>(
        key: _salesKey,
        loader: _loadSalesForStartup,
        target: _sales,
        afterLoad: () {
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
        },
      );

  Future<void> ensureSaleQuotationsLoaded() =>
      _loadDeferredGroup<SaleQuotation>(
        key: _saleQuotationsKey,
        loader: _loadSaleQuotationsForStartup,
        target: _saleQuotations,
      );

  Future<void> ensureDeliveryNotesLoaded() => _loadDeferredGroup<DeliveryNote>(
        key: _deliveryNotesKey,
        loader: _loadDeliveryNotesForStartup,
        target: _deliveryNotes,
        afterLoad: () {
          _touchDataRevisions(deliveryNotes: true);
          _invalidateDerivedDataCaches();
        },
      );

  Future<void> ensureBillsOfMaterialsLoaded() =>
      _loadDeferredGroup<BillOfMaterials>(
        key: _billsOfMaterialsKey,
        loader: _loadBillsOfMaterialsForStartup,
        target: _billsOfMaterials,
      );

  Future<void> ensureManufacturingOrdersLoaded() =>
      _loadDeferredGroup<ManufacturingOrder>(
        key: _manufacturingOrdersKey,
        loader: _loadManufacturingOrdersForStartup,
        target: _manufacturingOrders,
      );

  Future<void> ensureSuppliersLoaded() => _loadDeferredGroup<Supplier>(
        key: _suppliersKey,
        loader: _loadSuppliersForStartup,
        target: _suppliers,
        afterLoad: () {
          _rebuildSupplierIndexes();
          _touchDataRevisions(suppliers: true);
        },
      );

  Future<void> ensureSupplierProductPricesLoaded() =>
      _loadDeferredGroup<SupplierProductPrice>(
        key: _supplierProductPricesKey,
        loader: _loadSupplierProductPricesForStartup,
        target: _supplierProductPrices,
        afterLoad: () {
          _touchDataRevisions(supplierProductPrices: true);
        },
      );

  Future<void> ensurePriceListsLoaded() => _loadDeferredGroup<PriceList>(
        key: _priceListsKey,
        loader: _loadPriceListsForStartup,
        target: _priceLists,
        afterLoad: () {
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> ensureProductPricesLoaded() => _loadDeferredGroup<ProductPrice>(
        key: _productPricesKey,
        loader: _loadProductPricesForStartup,
        target: _productPrices,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureDefaultProductPriceEntries();
        },
      );

  Future<void> ensureProductPriceOverridesLoaded() =>
      _loadDeferredGroup<ProductPriceOverride>(
        key: _productPriceOverridesKey,
        loader: _loadProductPriceOverridesForStartup,
        target: _productPriceOverrides,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
        },
      );

  Future<void> ensureProductCostsLoaded() => _loadDeferredGroup<ProductCost>(
        key: _productCostsKey,
        loader: _loadProductCostsForStartup,
        target: _productCosts,
        afterLoad: () {
          _rebuildProductPricingLookupCaches();
          _ensureProductCostEntries();
        },
      );

  Future<void> ensureCostingMethodHistoryLoaded() =>
      _loadDeferredGroup<CostingMethodHistory>(
        key: _costingMethodHistoryKey,
        loader: _loadCostingMethodHistoryForStartup,
        target: _costingMethodHistory,
        afterLoad: () {
          _ensureCostingMethodHistory();
        },
      );

  Future<void> ensureInventoryCostLayersLoaded() =>
      _loadDeferredGroup<InventoryCostLayer>(
        key: _inventoryCostLayersKey,
        loader: _loadInventoryCostLayersForStartup,
        target: _inventoryCostLayers,
      );

  Future<void> ensureExpensesLoaded() => _loadDeferredGroup<Expense>(
        key: _expensesKey,
        loader: _loadExpensesForStartup,
        target: _expenses,
        afterLoad: () {
          _rebuildExpenseIndexes();
          _touchDataRevisions(expenses: true);
        },
      );

  Future<void> ensurePurchasesLoaded() => _loadDeferredGroup<Purchase>(
        key: _purchasesKey,
        loader: _loadPurchasesForStartup,
        target: _purchases,
        afterLoad: () {
          _rebuildPurchaseIndexes();
          _touchDataRevisions(purchases: true);
        },
      );

  Future<void> ensureStockMovementsLoaded() =>
      _loadDeferredGroup<StockMovement>(
        key: _stockMovementsKey,
        loader: _loadStockMovementsForStartup,
        target: _stockMovements,
        afterLoad: () {
          _rebuildStockMovementIndexes();
          _touchDataRevisions(stockMovements: true);
        },
      );

  Future<void> ensureInventoryCountsLoaded() =>
      _loadDeferredGroup<InventoryCountSession>(
        key: _inventoryCountsKey,
        loader: _loadInventoryCountsForStartup,
        target: _inventoryCounts,
        afterLoad: () {
          _touchDataRevisions(inventoryCounts: true);
        },
      );

  Future<void> ensureWarehousesLoaded() => _loadDeferredGroup<Warehouse>(
        key: _warehousesKey,
        loader: _loadWarehousesForStartup,
        target: _warehouses,
        afterLoad: () {
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
        },
      );

  Future<void> ensureAccountTransactionsLoaded() =>
      _loadDeferredGroup<AccountTransaction>(
        key: _accountTransactionsKey,
        loader: _loadAccountTransactionsForStartup,
        target: _accountTransactions,
        afterLoad: () {
          _rebuildAccountTransactionIndexes();
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
        },
      );

  Future<void> ensureProductPricingLoaded() async {
    await ensureProductsLoaded();
    await ensurePriceListsLoaded();
    await ensureProductPricesLoaded();
    await ensureProductPriceOverridesLoaded();
  }

  Future<void> ensureProductCostingDataLoaded() async {
    await ensureProductsLoaded();
    await ensureProductCostsLoaded();
    await ensureCostingMethodHistoryLoaded();
    await ensureInventoryCostLayersLoaded();
    await ensureSupplierProductPricesLoaded();
  }

  Future<void> ensureSalesPageDataLoaded() async {
    await ensureProductsLoaded();
    await Future.wait([
      ensureCustomersLoaded(),
      ensureDeliveryNotesLoaded(),
      ensureProductPricingLoaded(),
    ]);
  }

  Future<void> ensurePurchasesPageDataLoaded() async {
    await ensureProductsLoaded();
    await ensureSuppliersLoaded();
    await ensureSupplierProductPricesLoaded();
  }

  Future<void> ensureAccountingPageDataLoaded() async {
    await ensureCustomersLoaded();
    await ensureSuppliersLoaded();
    await ensureSalesLoaded();
    await ensurePurchasesLoaded();
    await ensureAccountTransactionsLoaded();
  }

  Future<void> ensureQuotationsPageDataLoaded() async {
    await ensureProductsLoaded();
    await ensureCustomersLoaded();
    await ensureSaleQuotationsLoaded();
  }

  Future<void> ensureDeliveryNotesPageDataLoaded() async {
    await ensureSalesLoaded();
    await ensureDeliveryNotesLoaded();
  }

  Future<void> ensureInventoryPageDataLoaded() async {
    await ensureProductsLoaded();
    await ensureStockMovementsLoaded();
    await ensureInventoryCountsLoaded();
    await ensureWarehousesLoaded();
  }

  Future<void> ensureHeavyDataLoaded() async {
    await ensureProductsLoaded();
    await ensureCustomersLoaded();
    await ensureSalesLoaded();
    await ensureSaleQuotationsLoaded();
    await ensureDeliveryNotesLoaded();
    await ensureBillsOfMaterialsLoaded();
    await ensureManufacturingOrdersLoaded();
    await ensureSuppliersLoaded();
    await ensureSupplierProductPricesLoaded();
    await ensurePriceListsLoaded();
    await ensureProductPricesLoaded();
    await ensureProductPriceOverridesLoaded();
    await ensureProductCostsLoaded();
    await ensureCostingMethodHistoryLoaded();
    await ensureInventoryCostLayersLoaded();
    await ensureExpensesLoaded();
    await ensurePurchasesLoaded();
    await ensureStockMovementsLoaded();
    await ensureInventoryCountsLoaded();
    await ensureWarehousesLoaded();
    await ensureAccountTransactionsLoaded();
    await _requestSyncDataLoad();
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;
  }

  List<Product> get products {
    unawaited(ensureProductsLoaded());
    _ensureProductsCache();
    return _cachedProducts!;
  }

  Product? productById(String id) {
    final index = _productIndexById[id.trim()];
    if (index == null || index < 0 || index >= _products.length) return null;
    final product = _products[index];
    return product.isDeleted ? null : product;
  }

  void _ensureSalesCache() {
    if (_cachedSalesGeneration == _salesRevision && _cachedSales != null) {
      return;
    }
    _cachedSales = UnmodifiableListView(
      _sales
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedSalesGeneration = _salesRevision;
  }

  List<Product> get allProductsForDiagnostics => List.unmodifiable(_products);
  List<Customer> get allCustomersForDiagnostics =>
      List.unmodifiable(_customers);
  List<Supplier> get allSuppliersForDiagnostics =>
      List.unmodifiable(_suppliers);
  List<Customer> get customers {
    unawaited(ensureCustomersLoaded());
    return List.unmodifiable(
      _customers.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<Sale> get sales {
    unawaited(ensureSalesLoaded());
    _ensureSalesCache();
    return _cachedSales!;
  }

  List<SaleQuotation> get saleQuotations {
    unawaited(ensureSaleQuotationsLoaded());
    _ensureSaleQuotationsCache();
    return _cachedSaleQuotations!;
  }

  List<DeliveryNote> get deliveryNotes {
    unawaited(ensureDeliveryNotesLoaded());
    _ensureDeliveryNotesCache();
    return _cachedDeliveryNotes!;
  }

  List<BillOfMaterials> get billsOfMaterials {
    unawaited(ensureBillsOfMaterialsLoaded());
    _ensureBillsOfMaterialsCache();
    return _cachedBillsOfMaterials!;
  }

  List<ManufacturingOrder> get manufacturingOrders {
    unawaited(ensureManufacturingOrdersLoaded());
    _ensureManufacturingOrdersCache();
    return _cachedManufacturingOrders!;
  }

  List<Supplier> get suppliers {
    unawaited(ensureSuppliersLoaded());
    _ensureSuppliersCache();
    return _cachedSuppliers!;
  }

  List<SupplierProductPrice> get supplierProductPrices {
    unawaited(ensureSupplierProductPricesLoaded());
    _ensureSupplierProductPricesCache();
    return _cachedSupplierProductPrices!;
  }

  List<PriceList> get priceLists {
    unawaited(ensurePriceListsLoaded());
    _ensurePriceListsCache();
    return _cachedPriceLists!;
  }

  List<ProductPrice> get productPrices {
    unawaited(ensureProductPricesLoaded());
    _ensureProductPricesCache();
    return _cachedProductPrices!;
  }

  List<ProductPriceOverride> get productPriceOverrides {
    unawaited(ensureProductPriceOverridesLoaded());
    _ensureProductPriceOverridesCache();
    return _cachedProductPriceOverrides!;
  }

  List<ProductCost> get productCosts {
    unawaited(ensureProductCostsLoaded());
    _ensureProductCostsCache();
    return _cachedProductCosts!;
  }

  List<CostingMethodHistory> get costingMethodHistory {
    unawaited(ensureCostingMethodHistoryLoaded());
    _ensureCostingMethodHistoryCache();
    return _cachedCostingMethodHistory!;
  }

  InventoryCostingMethod get inventoryCostingMethod => _inventoryCostingMethod;

  List<InventoryCostLayer> get inventoryCostLayers {
    unawaited(ensureInventoryCostLayersLoaded());
    _ensureInventoryCostLayersCache();
    return _cachedInventoryCostLayers!;
  }

  ProductCost productCostFor(String productId) {
    _ensureProductPricingLookupCaches();
    return _productCostByProductId[productId] ??
        ProductCost(productId: productId);
  }

  PriceList get defaultPriceList {
    _ensureDefaultPriceLists();
    return _priceLists.firstWhere((item) => item.isDefault && item.isActive,
        orElse: () => _priceLists.first);
  }

  ProductPrice? defaultProductPriceFor(String productId,
      {String unitId = 'base'}) {
    _ensureProductPricingLookupCaches();
    _ensureDefaultProductPriceEntries();
    final priceListId = defaultPriceList.id;
    return _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)];
  }

  ProductPriceOverride? productPriceOverrideFor(
      ProductPrice price, String currencyCode) {
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    for (final item in _productPriceOverrides) {
      if (item.productPriceId == price.id &&
          item.currencyCode == normalizedCurrency &&
          item.isActive) {
        return item;
      }
    }
    return null;
  }

  double productPriceAmountForCurrency(Product product, String currencyCode,
      {String unitId = 'base'}) {
    final price = defaultProductPriceFor(product.id, unitId: unitId);
    if (price == null) {
      final fallbackUsd = unitId == 'base' ? product.usdPrice : product.price;
      return fromUsdReferencePrice(fallbackUsd, currencyCode, storeProfile);
    }
    final override = productPriceOverrideFor(price, currencyCode);
    if (override != null) {
      return override.amount;
    }
    return convertCurrency(
      price.baseAmount,
      price.baseCurrencyCode,
      currencyCode.trim().toUpperCase(),
      storeProfile,
    );
  }

  double defaultProductUsdPrice(Product product, {String unitId = 'base'}) {
    final price = defaultProductPriceFor(product.id, unitId: unitId);
    if (price == null) {
      return unitId == 'base' ? product.usdPrice : product.price;
    }
    final saleCurrency = storeProfile.defaultSaleInvoiceCurrency;
    final override = productPriceOverrideFor(price, saleCurrency);
    if (override != null) {
      return toUsdReferencePrice(
          override.amount, override.currencyCode, storeProfile);
    }
    return toUsdReferencePrice(
        price.baseAmount, price.baseCurrencyCode, storeProfile);
  }

  List<SupplierProductPrice> get allSupplierProductPricesForDiagnostics =>
      List.unmodifiable(_supplierProductPrices);
  List<CatalogItem> get categories {
    return List.unmodifiable(
      _categories.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<CatalogItem> get brands {
    return List.unmodifiable(
      _brands.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<CatalogItem> get units {
    return List.unmodifiable(
      _units.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<DataConflict> get dataConflicts {
    unawaited(ensureHeavyDataLoaded());
    return List.unmodifiable(_detectDataConflicts());
  }

  int get dataConflictCount => dataConflicts.length;
  int get blockingDataConflictCount =>
      dataConflicts.where((item) => item.blocking).length;
  List<Expense> get expenses {
    unawaited(ensureExpensesLoaded());
    return List.unmodifiable(
      _expenses
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  List<Purchase> get purchases {
    unawaited(ensurePurchasesLoaded());
    return List.unmodifiable(
      _purchases
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  List<StockMovement> get stockMovements {
    unawaited(ensureStockMovementsLoaded());
    return List.unmodifiable(
      _stockMovements.toList(growable: false).reversed.toList(growable: false),
    );
  }

  List<StockMovement> get autoCorrectionMovements => List.unmodifiable(
        _stockMovements
            .where((movement) => movement.type == 'auto_correction')
            .toList()
            .reversed,
      );
  List<StockMovement> get pendingAutoCorrectionMovements => List.unmodifiable(
        _stockMovements
            .where(
              (movement) =>
                  movement.type == 'auto_correction' && !movement.isReviewed,
            )
            .toList()
            .reversed,
      );
  int get pendingAutoCorrectionCount => pendingAutoCorrectionMovements.length;
  List<InventoryCountSession> get inventoryCountSessions {
    unawaited(ensureInventoryCountsLoaded());
    return List.unmodifiable(
      _inventoryCounts.toList(growable: false).reversed.toList(growable: false),
    );
  }

  InventoryCountSession? get activeInventoryCountSession {
    for (final session in _inventoryCounts.reversed) {
      if (session.isOpen) return session;
    }
    return null;
  }

  List<Warehouse> get warehouses {
    unawaited(ensureWarehousesLoaded());
    return List.unmodifiable(
      _warehouses
          .where((item) => !item.isDeleted && item.isActive)
          .toList(growable: false),
    );
  }

  Warehouse get defaultWarehouse {
    _ensureDefaultWarehouse();
    return _warehouses.firstWhere(
      (item) => item.id == Warehouse.defaultId,
      orElse: () => Warehouse(
        id: Warehouse.defaultId,
        name: Warehouse.defaultName,
        isDefault: true,
      ),
    );
  }

  void _ensureDefaultWarehouse() {
    if (_warehouses.any(
      (item) => item.id == Warehouse.defaultId && !item.isDeleted,
    )) {
      return;
    }
    final now = DateTime.now();
    _warehouses.insert(
      0,
      Warehouse(
        id: Warehouse.defaultId,
        name: Warehouse.defaultName,
        code: 'MAIN',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
    );
    _rememberSqliteDirtyBusinessRow(
      _warehousesKey,
      _warehouses.first.toJson(),
    );
  }

  void _invalidateDerivedDataCaches() {
    _derivedListCacheGeneration += 1;
    _warehouseStockCacheDirty = true;
    _purchaseInsightsCacheDirty = true;
  }

  @override
  void notifyListeners() {
    _storeRevision += 1;
    _invalidateDerivedDataCaches();
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] notifyListeners device=$_deviceId '
      'role=${appIdentity.deviceRole.name} customers=${_customers.length} '
      'sales=${_sales.length} accounts=${_accountTransactions.length} '
      'seq=$_syncSequence pendingQueue=${_syncQueue.length} '
      'pendingChanges=${_syncChanges.length}',
    );
    super.notifyListeners();
  }

  int get storeRevision => _storeRevision;

  bool _isDerivedCacheCurrent(int generation) =>
      generation == _derivedListCacheGeneration;

  void _ensureSaleQuotationsCache() {
    if (_isDerivedCacheCurrent(_cachedSaleQuotationsGeneration) &&
        _cachedSaleQuotations != null) {
      return;
    }
    _cachedSaleQuotations = UnmodifiableListView(
      _saleQuotations
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedSaleQuotationsGeneration = _derivedListCacheGeneration;
  }

  void _ensureDeliveryNotesCache() {
    if (_isDerivedCacheCurrent(_cachedDeliveryNotesGeneration) &&
        _cachedDeliveryNotes != null) {
      return;
    }
    _cachedDeliveryNotes = UnmodifiableListView(
      _deliveryNotes
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedDeliveryNotesGeneration = _derivedListCacheGeneration;
  }

  void _ensureDeliveryNoteLookupCache() {
    if (_isDerivedCacheCurrent(_cachedDeliveryNoteBySaleIdGeneration) &&
        _cachedDeliveryNoteBySaleId != null) {
      return;
    }
    final bySaleId = <String, DeliveryNote>{};
    for (final note in _deliveryNotes) {
      if (note.isDeleted) continue;
      final saleId = note.saleId.trim();
      if (saleId.isEmpty) continue;
      bySaleId[saleId] = note;
    }
    _cachedDeliveryNoteBySaleId = bySaleId;
    _cachedDeliveryNoteBySaleIdGeneration = _derivedListCacheGeneration;
  }

  void _ensureBillsOfMaterialsCache() {
    if (_isDerivedCacheCurrent(_cachedBillsOfMaterialsGeneration) &&
        _cachedBillsOfMaterials != null) {
      return;
    }
    _cachedBillsOfMaterials = UnmodifiableListView(
      _billsOfMaterials
          .where((item) => !item.isDeleted && item.isActive)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedBillsOfMaterialsGeneration = _derivedListCacheGeneration;
  }

  void _ensureManufacturingOrdersCache() {
    if (_isDerivedCacheCurrent(_cachedManufacturingOrdersGeneration) &&
        _cachedManufacturingOrders != null) {
      return;
    }
    _cachedManufacturingOrders = UnmodifiableListView(
      _manufacturingOrders
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
    _cachedManufacturingOrdersGeneration = _derivedListCacheGeneration;
  }

  void _ensureSuppliersCache() {
    if (_cachedSuppliersGeneration == _suppliersRevision &&
        _cachedSuppliers != null) {
      return;
    }
    _cachedSuppliers = UnmodifiableListView(
      _suppliers.where((item) => !item.isDeleted).toList(growable: false),
    );
    _cachedSuppliersGeneration = _suppliersRevision;
  }

  void _ensureSupplierProductPricesCache() {
    if (_cachedSupplierProductPricesGeneration ==
            _supplierProductPricesRevision &&
        _cachedSupplierProductPrices != null) {
      return;
    }
    _cachedSupplierProductPrices = UnmodifiableListView(
      _supplierProductPrices
          .where((item) => !item.isDeleted)
          .toList(growable: false),
    );
    _cachedSupplierProductPricesGeneration = _supplierProductPricesRevision;
  }

  void _ensurePriceListsCache() {
    if (_cachedPriceListsGeneration == _productsRevision &&
        _cachedPriceLists != null) {
      return;
    }
    _cachedPriceLists = UnmodifiableListView(
      _priceLists.where((item) => item.isActive).toList(growable: false),
    );
    _cachedPriceListsGeneration = _productsRevision;
  }

  void _ensureProductPricesCache() {
    if (_cachedProductPricesGeneration == _productsRevision &&
        _cachedProductPrices != null) {
      return;
    }
    _cachedProductPrices = UnmodifiableListView(
      _productPrices.where((item) => item.isActive).toList(growable: false),
    );
    _cachedProductPricesGeneration = _productsRevision;
  }

  void _ensureProductPriceOverridesCache() {
    if (_cachedProductPriceOverridesGeneration == _productsRevision &&
        _cachedProductPriceOverrides != null) {
      return;
    }
    _cachedProductPriceOverrides = UnmodifiableListView(
      _productPriceOverrides
          .where((item) => item.isActive)
          .toList(growable: false),
    );
    _cachedProductPriceOverridesGeneration = _productsRevision;
  }

  void _ensureProductCostsCache() {
    if (_cachedProductCostsGeneration == _productsRevision &&
        _cachedProductCosts != null) {
      return;
    }
    _cachedProductCosts = UnmodifiableListView(
      _productCosts.toList(growable: false),
    );
    _cachedProductCostsGeneration = _productsRevision;
  }

  void _ensureCostingMethodHistoryCache() {
    if (_cachedCostingMethodHistoryGeneration == _productsRevision &&
        _cachedCostingMethodHistory != null) {
      return;
    }
    _cachedCostingMethodHistory = UnmodifiableListView(
      _costingMethodHistory.toList(growable: false)
        ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom)),
    );
    _cachedCostingMethodHistoryGeneration = _productsRevision;
  }

  void _ensureInventoryCostLayersCache() {
    if (_cachedInventoryCostLayersGeneration == _productsRevision &&
        _cachedInventoryCostLayers != null) {
      return;
    }
    _cachedInventoryCostLayers = UnmodifiableListView(
      _inventoryCostLayers.toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
    _cachedInventoryCostLayersGeneration = _productsRevision;
  }

  void _rebuildInventoryCostLayerLookupCache() {
    _inventoryCostLayerIndexById.clear();
    for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
      final id = _inventoryCostLayers[i].id.trim();
      if (id.isEmpty) continue;
      _inventoryCostLayerIndexById[id] = i;
    }
  }

  void _ensureWarehouseStockCache() {
    if (!_warehouseStockCacheDirty) return;
    _ensureDefaultWarehouse();
    final warehouseIds = _warehouses
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toList(growable: false);
    _warehouseStockByProductCache.clear();
    for (final product in _products.where((item) => !item.isDeleted)) {
      _warehouseStockByProductCache[product.id] = <String, double>{
        for (final id in warehouseIds) id: 0,
      };
    }

    for (final movement in _stockMovements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      final wid = movement.warehouseId.trim().isEmpty
          ? Warehouse.defaultId
          : movement.warehouseId.trim();
      final result = _warehouseStockByProductCache.putIfAbsent(
        productId,
        () => <String, double>{for (final id in warehouseIds) id: 0},
      );
      result[wid] = (result[wid] ?? 0) + movement.quantity;
    }

    for (final product in _products.where((item) => !item.isDeleted)) {
      final result = _warehouseStockByProductCache.putIfAbsent(
        product.id,
        () => <String, double>{for (final id in warehouseIds) id: 0},
      );
      final assigned = result.values.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      final unassignedLegacyStock = product.stock - assigned;
      if (unassignedLegacyStock != 0) {
        result[Warehouse.defaultId] =
            (result[Warehouse.defaultId] ?? 0) + unassignedLegacyStock;
      }
    }
    _warehouseStockCacheDirty = false;
  }

  double stockForWarehouse(String productId, String warehouseId) {
    _ensureWarehouseStockCache();
    final wid =
        warehouseId.trim().isEmpty ? Warehouse.defaultId : warehouseId.trim();
    return _warehouseStockByProductCache[productId]?[wid] ?? 0;
  }

  Map<String, double> warehouseStockForProduct(String productId) {
    _ensureWarehouseStockCache();
    return Map.unmodifiable(
      _warehouseStockByProductCache[productId] ?? const <String, double>{},
    );
  }

  List<AccountTransaction> get accountTransactions {
    unawaited(ensureAccountTransactionsLoaded());
    return List.unmodifiable(
      _accountTransactions
          .where((item) => !item.isDeleted)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  String _accountLedgerKey(String accountType, String accountId) =>
      '${accountType.trim().toLowerCase()}::${accountId.trim()}';

  void _invalidateAccountLedgerCache() {
    _accountLedgerCacheDirty = true;
  }

  bool _isLedgerTrackedAccountTransaction(AccountTransaction item) {
    if (item.isDeleted) return false;
    final type = item.accountType.trim().toLowerCase();
    if (type != 'customer' && type != 'supplier') return false;
    return item.accountId.trim().isNotEmpty;
  }

  void _removeAccountTransactionFromLedgerCache(AccountTransaction item) {
    if (_accountLedgerCacheDirty || !_isLedgerTrackedAccountTransaction(item)) {
      return;
    }
    final key = _accountLedgerKey(item.accountType, item.accountId);
    final balance = _accountBalanceCache[key];
    if (balance != null) {
      final nextBalance = balance - item.signedAmount;
      if (nextBalance.abs() < 0.000001) {
        _accountBalanceCache.remove(key);
      } else {
        _accountBalanceCache[key] = nextBalance;
      }
    }
    final rows = _accountTransactionsByAccountCache[key];
    if (rows == null) return;
    rows.removeWhere((row) => row.id == item.id);
    if (rows.isEmpty) {
      _accountTransactionsByAccountCache.remove(key);
    }
  }

  void _addAccountTransactionToLedgerCache(AccountTransaction item) {
    if (_accountLedgerCacheDirty || !_isLedgerTrackedAccountTransaction(item)) {
      return;
    }
    final key = _accountLedgerKey(item.accountType, item.accountId);
    _accountBalanceCache[key] =
        (_accountBalanceCache[key] ?? 0) + item.signedAmount;
    final rows =
        _accountTransactionsByAccountCache[key] ??= <AccountTransaction>[];
    rows.removeWhere((row) => row.id == item.id);
    rows.add(item);
    rows.sort((a, b) => b.date.compareTo(a.date));
  }

  void _replaceAccountTransactionInLedgerCache({
    AccountTransaction? previous,
    required AccountTransaction current,
  }) {
    if (_accountLedgerCacheDirty) return;
    if (previous != null) {
      _removeAccountTransactionFromLedgerCache(previous);
    }
    _addAccountTransactionToLedgerCache(current);
  }

  void _ensureAccountLedgerCache() {
    if (!_accountLedgerCacheDirty) return;
    _accountBalanceCache.clear();
    _accountTransactionsByAccountCache.clear();
    for (final item in _accountTransactions) {
      if (item.isDeleted) continue;
      final type = item.accountType.trim().toLowerCase();
      if (type != 'customer' && type != 'supplier') continue;
      final accountId = item.accountId.trim();
      if (accountId.isEmpty) continue;
      final key = _accountLedgerKey(type, accountId);
      _accountBalanceCache[key] =
          (_accountBalanceCache[key] ?? 0) + item.signedAmount;
      (_accountTransactionsByAccountCache[key] ??= <AccountTransaction>[]).add(
        item,
      );
    }
    for (final rows in _accountTransactionsByAccountCache.values) {
      rows.sort((a, b) => b.date.compareTo(a.date));
    }
    _accountLedgerCacheDirty = false;
  }

  List<AccountTransaction> accountTransactionsForAccount(
    String accountType,
    String accountId,
  ) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return List.unmodifiable(
      _accountTransactionsByAccountCache[_accountLedgerKey(
            accountType,
            accountId,
          )] ??
          const <AccountTransaction>[],
    );
  }

  double accountBalance(String accountType, String accountId) {
    _requestLedgerDataLoad();
    _ensureAccountLedgerCache();
    return _accountBalanceCache[_accountLedgerKey(accountType, accountId)] ?? 0;
  }

  static const List<String> databaseEditableEntities = [
    'products',
    'customers',
    'suppliers',
    'supplierProductPrices',
    'expenses',
    'categories',
    'brands',
    'units',
  ];

  List<Map<String, dynamic>> databaseRows(String entity) {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        return List.unmodifiable(
          _products
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'customers':
        return List.unmodifiable(
          _customers
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'suppliers':
        return List.unmodifiable(
          _suppliers
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'supplierProductPrices':
        return List.unmodifiable(
          _supplierProductPrices
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'expenses':
        return List.unmodifiable(
          _expenses
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'categories':
        return List.unmodifiable(
          _categories
              .where((item) => !item.isDeleted)
              .map((item) => item.toJson()),
        );
      case 'brands':
        return List.unmodifiable(
          _brands.where((item) => !item.isDeleted).map((item) => item.toJson()),
        );
      case 'units':
        return List.unmodifiable(
          _units.where((item) => !item.isDeleted).map((item) => item.toJson()),
        );
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> saveDatabaseRow(String entity, Map<String, dynamic> json) async {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        await addOrUpdateProduct(Product.fromJson(json));
        return;
      case 'customers':
        await addOrUpdateCustomer(Customer.fromJson(json));
        return;
      case 'suppliers':
        await addOrUpdateSupplier(Supplier.fromJson(json));
        return;
      case 'supplierProductPrices':
        await addOrUpdateSupplierProductPrice(
          SupplierProductPrice.fromJson(json),
        );
        return;
      case 'expenses':
        await addOrUpdateExpense(Expense.fromJson(json));
        return;
      case 'categories':
        await addOrUpdateCategory(CatalogItem.fromJson(json));
        return;
      case 'brands':
        await addOrUpdateBrand(CatalogItem.fromJson(json));
        return;
      case 'units':
        await addOrUpdateUnit(CatalogItem.fromJson(json));
        return;
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> deleteDatabaseRow(String entity, String id) async {
    requirePermission(AppPermission.databaseManage);
    switch (entity) {
      case 'products':
        await deleteProduct(id);
        return;
      case 'customers':
        await deleteCustomer(id);
        return;
      case 'suppliers':
        await deleteSupplier(id);
        return;
      case 'supplierProductPrices':
        await deleteSupplierProductPrice(id);
        return;
      case 'expenses':
        await deleteExpense(id);
        return;
      case 'categories':
        await _deleteCatalogItem(_categories, 'category', id, categories: true);
        return;
      case 'brands':
        await _deleteCatalogItem(_brands, 'brand', id, brands: true);
        return;
      case 'units':
        await _deleteCatalogItem(_units, 'unit', id, units: true);
        return;
    }
    throw ArgumentError('Unsupported database entity: $entity');
  }

  Future<void> _deleteCatalogItem(
    List<CatalogItem> list,
    String entityType,
    String id, {
    bool categories = false,
    bool brands = false,
    bool units = false,
  }) async {
    requirePermission(AppPermission.catalogManage);
    final index = list.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    list[index] = _withSyncMeta<CatalogItem>(
      list[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _recordSyncChange(
      entityType: entityType,
      entityId: id,
      operation: 'delete',
      payload: list[index].toJson(),
    );
    await _saveDirty(
      categories: categories,
      brands: brands,
      units: units,
      sync: true,
    );
    notifyListeners();
  }

  List<SyncChange> get syncChanges {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncChanges);
  }

  int get currentSyncSequence => _syncSequence;
  int get latestStoredAuthoritativeSequence =>
      _latestStoredAuthoritativeSequence();
  List<SyncQueueItem> get syncQueue {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncQueue);
  }

  List<SyncQueueItem> get pendingSyncQueue {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncQueue.where((item) => item.isPending));
  }

  List<SyncChange> get pendingSyncChanges {
    _requestSyncDataLoad();
    return List.unmodifiable(_syncChanges.where((item) => !item.isSynced));
  }

  List<SyncQueueItem> pendingSyncQueueForTarget(
    String target, {
    bool readyOnly = true,
  }) {
    _requestSyncDataLoad();
    final items = _syncQueue.where(
      (item) => item.target == target && item.isPending,
    );
    return List.unmodifiable(
      readyOnly ? items.where((item) => item.isReadyToSend) : items,
    );
  }

  List<SyncChange> pendingSyncChangesForTarget(
    String target, {
    bool readyOnly = true,
  }) {
    _requestSyncDataLoad();
    final queueItems = pendingSyncQueueForTarget(target, readyOnly: readyOnly);
    final ids = queueItems.map((item) => item.changeId).toSet();
    return List.unmodifiable(
      _syncChanges.where(
        (change) => ids.contains(change.id) && !change.isSynced,
      ),
    );
  }

  List<SyncChange> submittedSyncChangesForTarget(String target) {
    _requestSyncDataLoad();
    final ids = _syncQueue
        .where((item) => item.target == target && item.status == 'submitted')
        .map((item) => item.changeId)
        .toSet();
    return List.unmodifiable(
      _syncChanges.where(
        (change) => ids.contains(change.id) && !change.isSynced,
      ),
    );
  }

  String get deviceId => _deviceId;
  int get pendingSyncCount => pendingSyncQueue.length;
  int get pendingSyncQueueCount => pendingSyncQueue.length;

  String get activeClientSyncTarget {
    if (!appIdentity.isClient) return '';
    final active = appIdentity.activeSyncTransportNormalized;
    if (active == 'lan') return 'host';
    if (active == 'cloud') return 'cloud_host';
    return '';
  }

  int get activeClientPendingSyncCount {
    _requestSyncDataLoad();
    final target = activeClientSyncTarget;
    if (target.isEmpty) return pendingSyncCount;
    return pendingSyncQueueForTarget(target, readyOnly: false).length;
  }

  DateTime? get latestResetSyncAt {
    _requestSyncDataLoad();
    DateTime? latest;
    for (final change in _syncChanges) {
      if (change.entityType == 'system' &&
          change.operation == 'reset_store_data') {
        if (latest == null || change.createdAt.isAfter(latest)) {
          latest = change.createdAt;
        }
      }
    }
    return latest;
  }

  StoreProfile get storeProfile => _storeProfile;
  String get currentRole => currentUserRole?.name ?? _currentRole;
  List<UserRole> get roles => List.unmodifiable(_roles);
  List<AppUser> get users => List.unmodifiable(_users);
  AppUser? get activeUser => _activeUser;
  bool get rememberLogin => _rememberLogin;
  AppUser? get currentUser => _activeUser;
  AppIdentity get appIdentity =>
      _appIdentity ??
      AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform());
  UserRole? get currentUserRole =>
      _activeUser == null ? null : roleById(_activeUser!.roleId);
  bool get isAdmin =>
      _activeUser?.roleId == 'admin' || currentUserRole?.isAdmin == true;
  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any(hasPermission);
  bool canAccessPage(String pageId) {
    final page = AppPermission.pageById(pageId);
    if (page == null) return false;
    final permissions = page.navigationPermissions.isEmpty
        ? page.permissions
        : page.navigationPermissions;
    return hasAnyPermission(permissions);
  }

  bool get canViewDashboard => canAccessPage('dashboard');
  bool get canViewProducts => hasAnyPermission(<String>{
        AppPermission.productsView,
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  bool get canManageProducts => hasAnyPermission(<String>{
        AppPermission.productsManage,
        AppPermission.productsCreate,
        AppPermission.productsEdit,
        AppPermission.productsDelete,
      });
  bool get canViewCustomers => hasAnyPermission(<String>{
        AppPermission.customersView,
        AppPermission.customersManage,
      });
  bool get canManageCustomers => hasPermission(AppPermission.customersManage);
  bool get canViewSuppliers => hasAnyPermission(<String>{
        AppPermission.suppliersView,
        AppPermission.suppliersManage,
      });
  bool get canManageSuppliers => hasPermission(AppPermission.suppliersManage);
  bool get canViewSales => hasAnyPermission(<String>{
        AppPermission.salesView,
        AppPermission.salesCreate,
        AppPermission.salesCancel,
      });
  bool get canSell => hasPermission(AppPermission.salesCreate);
  bool get canViewQuotations => canAccessPage('quotations');
  bool get canManageQuotations => hasPermission(AppPermission.quotationsManage);
  bool get canViewDeliveryNotes => canAccessPage('delivery_notes');
  bool get canManageDeliveryNotes =>
      hasPermission(AppPermission.deliveryNotesManage);
  bool get canViewPurchases => canAccessPage('purchases');
  bool get canManagePurchases => hasAnyPermission(<String>{
        AppPermission.purchasesManage,
        AppPermission.suppliersManage,
      });
  bool get canViewExpenses => canAccessPage('expenses');
  bool get canManageExpenses => hasPermission(AppPermission.expensesManage);
  bool get canViewAccounting => canAccessPage('accounting');
  bool get canManageAccounting => hasPermission(AppPermission.accountingManage);
  bool get canViewInventory => canAccessPage('inventory');
  bool get canManageInventory => hasAnyPermission(<String>{
        AppPermission.inventoryWarehousesManage,
        AppPermission.inventoryMovementsView,
        AppPermission.inventoryCorrectionsManage,
        AppPermission.inventoryCountsManage,
        AppPermission.inventoryWasteManage,
        AppPermission.inventoryManufacturingManage,
      });
  bool get canViewReports => canAccessPage('reports');
  bool get canViewSettings => canAccessPage('settings');
  bool get canViewDatabase => canAccessPage('database');
  bool get canViewMaintenance => canAccessPage('maintenance');
  bool get canManageMaintenance =>
      hasPermission(AppPermission.maintenanceManage);
  bool get canManageUsers => hasAnyPermission(
      <String>{AppPermission.usersManage, AppPermission.rolesManage});
  bool get canManageUsersPage => hasAnyPermission(
      <String>{AppPermission.usersManage, AppPermission.rolesManage});
  bool get canManageDatabase => hasPermission(AppPermission.databaseManage);
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  bool get needsInitialAdminSetup =>
      _users.isEmpty || _hasOnlyLegacyDefaultAdminUser;
  bool get hasLocalAdminUser =>
      _users.any((item) => item.roleId == 'admin' && item.isActive);
  bool get hasLocalStoreData {
    final hasRealUser = _users.isNotEmpty && !_hasOnlyLegacyDefaultAdminUser;
    return hasRealUser ||
        _products.any((item) => !item.isDeleted) ||
        _customers.any((item) => !item.isDeleted) ||
        _sales.any((item) => !item.isDeleted) ||
        _saleQuotations.any((item) => !item.isDeleted) ||
        _deliveryNotes.any((item) => !item.isDeleted) ||
        _billsOfMaterials.any((item) => !item.isDeleted) ||
        _manufacturingOrders.any((item) => !item.isDeleted) ||
        _suppliers.any((item) => !item.isDeleted) ||
        _expenses.any((item) => !item.isDeleted) ||
        _purchases.any((item) => !item.isDeleted) ||
        _stockMovements.isNotEmpty ||
        _inventoryCounts.isNotEmpty ||
        _accountTransactions.any((item) => !item.isDeleted);
  }

  bool get isSuspendedByHost =>
      appIdentity.isClient && ClientSuspensionStateStore.isSuspended;
  String get suspendedByHostReason => ClientSuspensionStateStore.reason;

  Future<void> markSuspendedByHost({String reason = ''}) async {
    if (!appIdentity.isClient) return;
    await ClientSuspensionStateStore.markSuspended(reason: reason);
    if (_activeUser != null || _rememberLogin) {
      _activeUser = null;
      _rememberLogin = false;
      await LocalDatabaseService.setString(_activeUserKey, '');
      await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    }
    notifyListeners();
  }

  Future<void> clearSuspendedByHost() async {
    if (!appIdentity.isClient) return;
    if (!ClientSuspensionStateStore.isSuspended) return;
    await ClientSuspensionStateStore.clear();
    notifyListeners();
  }

  Future<ThemeMode> loadThemeMode() async {
    final raw = LocalDatabaseService.getString(_themeModeKey) ?? 'system';
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await LocalDatabaseService.setString(_themeModeKey, mode.name);
  }

  Future<Locale> loadLocale() async {
    final raw = LocalDatabaseService.getString(_localeKey) ?? 'en';
    return ['en', 'ar'].contains(raw) ? Locale(raw) : const Locale('en');
  }

  Future<void> saveLocale(Locale locale) async {
    final languageCode =
        ['en', 'ar'].contains(locale.languageCode) ? locale.languageCode : 'en';
    await LocalDatabaseService.setString(_localeKey, languageCode);
  }

  Map<String, dynamic> _loadDevFeatureFlags() {
    final raw = LocalDatabaseService.getString(_devFeatureFlagsKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Keep Developer/QA feature gates safe-by-default if the local setting is malformed.
    }
    return <String, dynamic>{};
  }

  bool get isStressLabEnabled {
    final flags = _loadDevFeatureFlags();
    final value = flags[_stressLabEnabledFlag];
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return false;
  }

  Future<void> setStressLabEnabled(bool enabled) async {
    final flags = _loadDevFeatureFlags();
    flags[_stressLabEnabledFlag] = enabled;
    flags['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await LocalDatabaseService.setString(
      _devFeatureFlagsKey,
      jsonEncode(flags),
    );
    notifyListeners();
  }

  bool get _hasOnlyLegacyDefaultAdminUser {
    if (_users.length != 1) return false;
    final user = _users.first;
    final legacyPassword = String.fromCharCodes(const [
      97,
      100,
      109,
      105,
      110,
      49,
      50,
      51,
    ]);
    return user.id == 'admin' &&
        user.username.trim().toLowerCase() == 'admin' &&
        _verifyPassword(legacyPassword, user.passwordHash) &&
        user.lastLoginAt == null;
  }

  Future<void> completeInitialAdminSetup({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final cleanName = fullName.trim().isEmpty ? 'Admin' : fullName.trim();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (cleanUsername.length < 3) {
      throw ArgumentError('Username must be at least 3 characters.');
    }
    if (cleanPassword.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    if (_users.isNotEmpty && !_hasOnlyLegacyDefaultAdminUser) {
      throw StateError('Initial administrator setup is already complete.');
    }
    final now = DateTime.now();
    final platform = _detectPlatform();
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot create a Host. Use Connect to Store from Web.',
      );
    }
    final legacyIndex = _hasOnlyLegacyDefaultAdminUser ? 0 : -1;
    if (legacyIndex == -1 &&
        _users.any(
          (user) => user.username.trim().toLowerCase() == cleanUsername,
        )) {
      throw StateError('Username already exists.');
    }
    final passwordHash = await _hashPasswordAsync(cleanPassword);
    final hostIdentity = _normalizedLocalIdentity(
      appIdentity.copyWith(
        deviceRole: DeviceRole.host,
        syncMode: appIdentity.syncMode == SyncMode.cloudConnected ||
                appIdentity.syncMode == SyncMode.marketplaceEnabled
            ? appIdentity.syncMode
            : SyncMode.lanOnly,
        hostDeviceId: '',
        platform: platform,
        updatedAt: now,
      ),
    );
    _assertSafeRoleTransition(
      hostIdentity,
      source: 'initial Host registration',
      allowInitialHostRegistration: true,
    );
    _assertLanCloudRoleRules(hostIdentity, source: 'initial Host registration');
    _appIdentity = hostIdentity;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(hostIdentity.toJson()),
    );
    final adminUser = legacyIndex == -1
        ? AppUser(
            id: 'admin_${now.microsecondsSinceEpoch}',
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          )
        : _users[legacyIndex].copyWith(
            fullName: cleanName,
            username: cleanUsername,
            passwordHash: passwordHash,
            updatedAt: now,
            lastLoginAt: now,
          );
    if (legacyIndex == -1) {
      _users.add(adminUser);
    } else {
      _users[legacyIndex] = adminUser;
    }
    _activeUser = adminUser;
    await LocalDatabaseService.setString(_activeUserKey, adminUser.id);
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> recoverOnlineStoreOwnerIdentity({
    required String storeId,
    required String branchId,
    required String storeName,
    required String username,
    required String password,
    String? hostDeviceId,
    String? deviceToken,
    String? cloudTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanBranchId = branchId.trim().toUpperCase();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (!RegExp(r'^ST-[A-Z0-9]{6,}$').hasMatch(cleanStoreId)) {
      throw ArgumentError('Online login did not return a valid Store ID.');
    }
    if (!RegExp(r'^BR-[A-Z0-9]{6,}$').hasMatch(cleanBranchId)) {
      throw ArgumentError('Online login did not return a valid Branch ID.');
    }
    if (cleanUsername.length < 3) {
      throw ArgumentError('Username must be at least 3 characters.');
    }
    if (cleanPassword.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    final platform = _detectPlatform();
    if (platform == AppPlatformType.web) {
      throw StateError(
        'Web devices cannot recover a Host. Use a desktop device, then import the backup.',
      );
    }

    final now = DateTime.now();
    final role = deviceRole ?? DeviceRole.host;
    final recoveredIdentity = _normalizedLocalIdentity(
      appIdentity.copyWith(
        storeId: cleanStoreId,
        branchId: cleanBranchId,
        deviceRole: role,
        // Online registration/recovery of the store owner identity must not
        // automatically enable Cloud Sync. Cloud Sync is a paid/explicit
        // feature and should only be enabled from the Sync settings page after
        // the user turns it on and the server allows it for this store.
        syncMode: syncMode ?? SyncMode.localOnly,
        activeSyncTransport: syncMode == SyncMode.cloudConnected ? 'cloud' : '',
        hostDeviceId: hostDeviceId ??
            (role == DeviceRole.host ? _deviceId : appIdentity.hostDeviceId),
        deviceToken: (deviceToken == null || deviceToken.trim().isEmpty)
            ? appIdentity.deviceToken
            : deviceToken.trim(),
        cloudTenantId: (cloudTenantId == null || cloudTenantId.trim().isEmpty)
            ? appIdentity.cloudTenantId
            : cloudTenantId.trim(),
        deviceId: _deviceId,
        platform: platform,
        updatedAt: now,
      ),
    );
    _assertLanCloudRoleRules(recoveredIdentity,
        source: 'online store recovery');
    _appIdentity = recoveredIdentity;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(recoveredIdentity.toJson()),
    );

    final cleanStoreName = storeName.trim();
    if (cleanStoreName.isNotEmpty) {
      _storeProfile = _storeProfile.copyWith(name: cleanStoreName);
      AccountingService.configureMoneyPolicy(_storeProfile);
    }

    final passwordHash = await _hashPasswordAsync(cleanPassword);
    final existingIndex = _users.indexWhere(
      (user) => user.username.trim().toLowerCase() == cleanUsername,
    );
    final recoveredUser = existingIndex == -1
        ? AppUser(
            id: 'owner_${now.microsecondsSinceEpoch}',
            fullName: cleanUsername,
            username: cleanUsername,
            passwordHash: passwordHash,
            roleId: 'admin',
            isSystem: true,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now,
          )
        : _users[existingIndex].copyWith(
            passwordHash: passwordHash,
            roleId: 'admin',
            updatedAt: now,
            lastLoginAt: now,
          );
    if (existingIndex == -1) {
      _users.add(recoveredUser);
    } else {
      _users[existingIndex] = recoveredUser;
    }
    _activeUser = recoveredUser;
    await LocalDatabaseService.setString(_activeUserKey, recoveredUser.id);
    await _saveRolesAndUsers();
    await _saveAll();
    notifyListeners();
  }

  UserRole? roleById(String id) {
    for (final role in _roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  bool hasPermission(String permission) {
    if (_activeUser == null) return false;
    final role = roleById(_activeUser!.roleId);
    if (role?.isAdmin == true) return true;
    final effective = <String>{
      ...?role?.permissions,
      ..._activeUser!.extraPermissions,
    };
    effective.removeAll(_activeUser!.deniedPermissions);
    return effective.contains(permission);
  }

  void requirePermission(String permission) {
    if (!hasPermission(permission)) {
      throw StateError('You do not have permission: $permission');
    }
  }

  double get totalSalesAmount =>
      sales.fold<double>(0, (sum, sale) => sum + sale.total);
  double get totalExpensesAmount => expensesOverview.totalExpensesAmount;
  double get totalPurchasesAmount => purchasesOverview.totalPurchasesAmount;
  int get pendingPurchaseCount => purchasesOverview.pendingPurchaseCount;

  PurchasesOverview get purchasesOverview {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month}';
    if (_cachedPurchasesOverviewRevision == _purchasesRevision &&
        _cachedPurchasesOverviewMonthKey == monthKey &&
        _cachedPurchasesOverview != null) {
      return _cachedPurchasesOverview!;
    }
    var totalCount = 0;
    var totalPurchasesAmount = 0.0;
    var monthlyTotal = 0.0;
    var monthlyCount = 0;
    var draftTotal = 0.0;
    var draftCount = 0;
    var receivedCount = 0;
    var returnedCount = 0;
    var cancelledCount = 0;

    for (final purchase in _purchases) {
      if (purchase.isDeleted) continue;
      totalCount += 1;
      final isCancelled = purchase.isCancelled;
      final isReceived = purchase.isReceived;
      final isReturned = purchase.isReturned;
      if (!isReceived && !isCancelled) draftCount += 1;
      if (isReceived && !isReturned) receivedCount += 1;
      if (isReturned) returnedCount += 1;
      if (purchase.status.toLowerCase() == 'cancelled') {
        cancelledCount += 1;
      }
      if (isCancelled) continue;
      totalPurchasesAmount += purchase.subtotal;
      if (purchase.date.year == now.year && purchase.date.month == now.month) {
        monthlyTotal += purchase.subtotal;
        monthlyCount += 1;
      }
      if (!isReceived) {
        draftTotal += purchase.subtotal;
      }
    }

    _cachedPurchasesOverview = PurchasesOverview(
      totalCount: totalCount,
      totalPurchasesAmount: totalPurchasesAmount,
      monthlyTotal: monthlyTotal,
      monthlyCount: monthlyCount,
      draftTotal: draftTotal,
      draftCount: draftCount,
      receivedCount: receivedCount,
      returnedCount: returnedCount,
      cancelledCount: cancelledCount,
      pendingPurchaseCount: draftCount,
    );
    _cachedPurchasesOverviewRevision = _purchasesRevision;
    _cachedPurchasesOverviewMonthKey = monthKey;
    return _cachedPurchasesOverview!;
  }

  ExpensesOverview get expensesOverview {
    if (_cachedExpensesOverviewRevision == _expensesRevision &&
        _cachedExpensesOverview != null) {
      return _cachedExpensesOverview!;
    }
    var totalCount = 0;
    var totalExpensesAmount = 0.0;
    var draftCount = 0;
    var postedCount = 0;
    var cancelledCount = 0;
    final categories = <String>{};
    for (final expense in _expenses) {
      if (expense.isDeleted) continue;
      totalCount += 1;
      final category = expense.category.trim();
      if (category.isNotEmpty) categories.add(category);
      if (expense.isDraft) draftCount += 1;
      if (expense.isPosted) {
        postedCount += 1;
        totalExpensesAmount += expense.amount;
      }
      if (expense.isCancelled) cancelledCount += 1;
    }
    _cachedExpensesOverview = ExpensesOverview(
      totalCount: totalCount,
      totalExpensesAmount: totalExpensesAmount,
      draftCount: draftCount,
      postedCount: postedCount,
      cancelledCount: cancelledCount,
      categoryCount: categories.length,
    );
    _cachedExpensesOverviewRevision = _expensesRevision;
    return _cachedExpensesOverview!;
  }

  void _ensurePurchaseInsightsCache() {
    if (!_purchaseInsightsCacheDirty) return;
    _purchaseHistoryByProductCache.clear();
    _purchaseMetricsByProductCache.clear();

    for (final purchase in _purchases.where(
      (item) => !item.isDeleted && !item.isCancelled,
    )) {
      for (final item in purchase.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        (_purchaseHistoryByProductCache[productId] ??=
                <SupplierPurchasePrice>[])
            .add(
          SupplierPurchasePrice(
            productId: item.productId,
            productName: item.productName,
            supplierId: purchase.supplierId,
            supplierName: purchase.supplierName,
            unitCost: item.unitCostPerBase,
            quantity: item.baseQuantity,
            purchaseId: purchase.id,
            purchaseNo: purchase.purchaseNo,
            date: purchase.date,
          ),
        );
      }
    }

    for (final entry in _purchaseHistoryByProductCache.entries) {
      final history = entry.value..sort((a, b) => b.date.compareTo(a.date));
      double totalQty = 0;
      double totalCost = 0;
      final suppliers = <String>{};
      for (final row in history) {
        totalQty += row.quantity;
        totalCost += row.quantity * row.unitCost;
        if (row.supplierId.trim().isNotEmpty) suppliers.add(row.supplierId);
      }
      _purchaseMetricsByProductCache[entry.key] = _ProductPurchaseMetrics(
        lastCost: history.isEmpty ? null : history.first.unitCost,
        averageCost: totalQty <= 0 ? 0 : totalCost / totalQty,
        supplierCount: suppliers.length,
      );
    }

    _purchaseInsightsCacheDirty = false;
  }

  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return List.unmodifiable(
      _purchaseHistoryByProductCache[productId] ??
          const <SupplierPurchasePrice>[],
    );
  }

  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  ) {
    _ensurePurchaseInsightsCache();
    final latestBySupplier = <String, SupplierPurchasePrice>{};
    for (final entry in _purchaseHistoryByProductCache[productId] ??
        const <SupplierPurchasePrice>[]) {
      latestBySupplier.putIfAbsent(entry.supplierId, () => entry);
    }
    final prices = latestBySupplier.values.toList()
      ..sort((a, b) => a.unitCost.compareTo(b.unitCost));
    return List.unmodifiable(prices);
  }

  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  }) {
    _ensurePurchaseInsightsCache();
    for (final entry in _purchaseHistoryByProductCache[productId] ??
        const <SupplierPurchasePrice>[]) {
      if (entry.supplierId == supplierId) return entry.unitCost;
    }
    return null;
  }

  double? lastPurchasePriceForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return _purchaseMetricsByProductCache[productId]?.lastCost;
  }

  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  }) {
    final sortedPurchases = _purchases
        .where(
          (purchase) =>
              !purchase.isDeleted &&
              !purchase.isCancelled &&
              purchase.supplierId == supplierId,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId == productId) return item;
      }
    }
    return null;
  }

  PurchaseItem? lastPurchaseItemForProduct(String productId) {
    final sortedPurchases = _purchases
        .where((purchase) => !purchase.isDeleted && !purchase.isCancelled)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId == productId) return item;
      }
    }
    return null;
  }

  double averagePurchaseCostForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return _purchaseMetricsByProductCache[productId]?.averageCost ?? 0;
  }

  void _seedSupplierProductPricesFromPurchaseHistory() {
    final latestByProductSupplier = <String, SupplierProductPrice>{};
    final sortedPurchases = _purchases
        .where((item) => !item.isDeleted && !item.isCancelled)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final purchase in sortedPurchases) {
      final supplierId = purchase.supplierId.trim();
      if (supplierId.isEmpty) continue;
      for (final item in purchase.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        final key = '$productId::$supplierId';
        latestByProductSupplier[key] = SupplierProductPrice(
          id: _supplierProductPriceId(productId, supplierId),
          productId: productId,
          supplierId: supplierId,
          cost: item.unitCostPerBase,
          currency: 'USD',
          createdAt: purchase.date,
          updatedAt: purchase.date,
          deviceId: purchase.deviceId,
          syncStatus: 'synced',
          storeId: purchase.storeId,
          branchId: purchase.branchId,
          version: 1,
          lastModifiedByDeviceId: purchase.lastModifiedByDeviceId,
        );
      }
    }
    if (latestByProductSupplier.isEmpty) return;
    _supplierProductPrices
      ..clear()
      ..addAll(latestByProductSupplier.values);
    _markSingleSupplierPerProductAsPreferred();
  }

  int _seedSupplierProductPricesFromLegacyProductSuppliers({
    bool recordSyncChanges = false,
  }) {
    final supplierByLegacyName = <String, Supplier>{};
    for (final supplier in _suppliers.where((item) => !item.isDeleted)) {
      for (final name in <String>[
        supplier.name,
        supplier.nameEn,
        supplier.nameAr,
        supplier.id,
      ]) {
        final key = _normalizeLegacySupplierName(name);
        if (key.isNotEmpty) {
          supplierByLegacyName.putIfAbsent(key, () => supplier);
        }
      }
    }

    final existingPairs = _supplierProductPrices
        .where((item) => !item.isDeleted)
        .map((item) => '${item.productId}::${item.supplierId}')
        .toSet();
    var added = 0;
    final now = DateTime.now();

    for (final product in _products.where((item) => !item.isDeleted)) {
      final legacySupplierName = product.supplier.trim();
      if (legacySupplierName.isEmpty) continue;
      final supplier = supplierByLegacyName[_normalizeLegacySupplierName(
        legacySupplierName,
      )];
      if (supplier == null) continue;
      final pairKey = '${product.id}::${supplier.id}';
      if (existingPairs.contains(pairKey)) continue;

      final price = SupplierProductPrice(
        id: _supplierProductPriceId(product.id, supplier.id),
        productId: product.id,
        supplierId: supplier.id,
        cost: _safeUsdCost(product),
        currency: 'USD',
        isPreferred: true,
        createdAt: product.createdAt,
        updatedAt: now,
        deviceId: product.deviceId.isNotEmpty ? product.deviceId : _deviceId,
        syncStatus: recordSyncChanges ? 'pending' : 'synced',
        storeId:
            product.storeId.isNotEmpty ? product.storeId : appIdentity.storeId,
        branchId: product.branchId.isNotEmpty
            ? product.branchId
            : appIdentity.branchId,
        version: 1,
        lastModifiedByDeviceId: product.lastModifiedByDeviceId.isNotEmpty
            ? product.lastModifiedByDeviceId
            : _deviceId,
      );
      _supplierProductPrices.add(price);
      existingPairs.add(pairKey);
      added += 1;
      if (recordSyncChanges) {
        _recordSyncChange(
          entityType: 'supplier_product_price',
          entityId: price.id,
          operation: 'create',
          payload: price.toJson(),
        );
      }
    }

    if (added > 0) {
      _markSingleSupplierPerProductAsPreferred();
    }
    return added;
  }

  void _markSingleSupplierPerProductAsPreferred() {
    final productSupplierCounts = <String, int>{};
    for (final item in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      productSupplierCounts[item.productId] =
          (productSupplierCounts[item.productId] ?? 0) + 1;
    }
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (!item.isDeleted &&
          productSupplierCounts[item.productId] == 1 &&
          !item.isPreferred) {
        _supplierProductPrices[i] = item.copyWith(isPreferred: true);
      }
    }
  }

  String _normalizeLegacySupplierName(String value) =>
      value.trim().toLowerCase();

  String _supplierProductPriceId(String productId, String supplierId) {
    final cleanProductId = productId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final cleanSupplierId = supplierId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return 'spp_${cleanProductId}_$cleanSupplierId';
  }

  int supplierCountForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return _purchaseMetricsByProductCache[productId]?.supplierCount ?? 0;
  }

  List<SupplierProductPrice> supplierProductPricesForProduct(String productId) {
    final rows = _supplierProductPrices
        .where((item) => !item.isDeleted && item.productId == productId)
        .toList()
      ..sort((a, b) {
        if (a.isPreferred != b.isPreferred) return a.isPreferred ? -1 : 1;
        return a.cost.compareTo(b.cost);
      });
    return List.unmodifiable(rows);
  }

  List<SupplierProductPrice> supplierProductPricesForSupplier(
    String supplierId,
  ) {
    final rows = _supplierProductPrices
        .where((item) => !item.isDeleted && item.supplierId == supplierId)
        .toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    return List.unmodifiable(rows);
  }

  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) {
    for (final item in _supplierProductPrices) {
      if (!item.isDeleted &&
          item.productId == productId &&
          item.supplierId == supplierId) {
        return item;
      }
    }
    return null;
  }

  SupplierProductPrice? preferredSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(productId);
    for (final item in rows) {
      if (item.isPreferred) return item;
    }
    return rows.isEmpty ? null : rows.first;
  }

  SupplierProductPrice? bestPriceSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(productId);
    if (rows.isEmpty) return null;
    final sorted = rows.toList()..sort((a, b) => a.cost.compareTo(b.cost));
    return sorted.first;
  }

  SupplierProductPrice? fastestSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(
      productId,
    ).where((item) => item.leadTimeDays != null).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.leadTimeDays!.compareTo(b.leadTimeDays!));
    return rows.first;
  }

  Future<void> addOrUpdateSupplierProductPrice(
    SupplierProductPrice price,
  ) async {
    requirePermission(AppPermission.suppliersManage);
    final cleanProductId = price.productId.trim();
    final cleanSupplierId = price.supplierId.trim();
    if (cleanProductId.isEmpty || cleanSupplierId.isEmpty) {
      throw ArgumentError(
        'Product and supplier are required for supplier price.',
      );
    }
    if (price.cost < 0) {
      throw ArgumentError('Supplier price cannot be negative.');
    }
    final now = DateTime.now();
    final existingIndex = _supplierProductPrices.indexWhere(
      (item) => item.id == price.id,
    );
    final duplicateIndex = _supplierProductPrices.indexWhere(
      (item) =>
          item.id != price.id &&
          !item.isDeleted &&
          item.productId == cleanProductId &&
          item.supplierId == cleanSupplierId,
    );
    final id = price.id.trim().isNotEmpty
        ? price.id.trim()
        : 'spp_${cleanProductId}_${cleanSupplierId}_${now.microsecondsSinceEpoch}';
    final previous = existingIndex != -1
        ? _supplierProductPrices[existingIndex]
        : (duplicateIndex != -1
            ? _supplierProductPrices[duplicateIndex]
            : null);
    final nextCurrency = price.currency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    final history = List<SupplierProductPriceHistoryEntry>.from(
      price.priceHistory,
    );
    if (previous != null &&
        ((previous.cost - price.cost).abs() > 0.0001 ||
            previous.currency.toUpperCase() != nextCurrency)) {
      history.add(
        SupplierProductPriceHistoryEntry(
          oldCost: previous.cost,
          newCost: price.cost,
          currency: nextCurrency,
          changedAt: now,
          source: 'manual',
        ),
      );
      if (history.length > 50) {
        history.removeRange(0, history.length - 50);
      }
    }
    var normalized = price.copyWith(
      id: id,
      productId: cleanProductId,
      supplierId: cleanSupplierId,
      currency: nextCurrency,
      supplierSku: price.supplierSku.trim(),
      minOrderQty: price.minOrderQty,
      clearMinOrderQty: price.minOrderQty == null,
      leadTimeDays: price.leadTimeDays,
      clearLeadTimeDays: price.leadTimeDays == null,
      priceHistory: history,
      createdAt: previous == null ? now : previous.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: previous == null ? price.version : previous.version + 1,
      lastModifiedByDeviceId: _deviceId,
      clearDeletedAt: true,
    );
    final changedPreferredRows = <SupplierProductPrice>[];
    if (normalized.isPreferred) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted &&
            item.productId == cleanProductId &&
            item.id != normalized.id &&
            item.isPreferred) {
          final updated = item.copyWith(
            isPreferred: false,
            updatedAt: now,
            syncStatus: 'pending',
            lastModifiedByDeviceId: _deviceId,
          );
          _supplierProductPrices[i] = updated;
          changedPreferredRows.add(updated);
        }
      }
    }
    final isCreate = existingIndex == -1 && duplicateIndex == -1;
    if (existingIndex != -1) {
      _supplierProductPrices[existingIndex] = normalized;
    } else if (duplicateIndex != -1) {
      normalized = normalized.copyWith(
        id: _supplierProductPrices[duplicateIndex].id,
        createdAt: _supplierProductPrices[duplicateIndex].createdAt,
      );
      _supplierProductPrices[duplicateIndex] = normalized;
    } else {
      _supplierProductPrices.add(normalized);
    }
    for (final changed in changedPreferredRows) {
      _recordSyncChange(
        entityType: 'supplier_product_price',
        entityId: changed.id,
        operation: 'update',
        payload: changed.toJson(),
      );
    }
    _recordSyncChange(
      entityType: 'supplier_product_price',
      entityId: normalized.id,
      operation: isCreate ? 'create' : 'update',
      payload: normalized.toJson(),
    );
    await _saveDirty(supplierProductPrices: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteSupplierProductPrice(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _supplierProductPrices.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _supplierProductPrices[index] = _supplierProductPrices[index].copyWith(
      deletedAt: DateTime.now(),
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    _recordSyncChange(
      entityType: 'supplier_product_price',
      entityId: id,
      operation: 'delete',
      payload: _supplierProductPrices[index].toJson(),
    );
    await _saveDirty(supplierProductPrices: true, sync: true);
    notifyListeners();
  }

  int get lowStockCount => products
      .where((product) => product.trackStock && product.isLowStock)
      .length;
  List<Product> get stockTrackedProducts {
    unawaited(ensureProductsLoaded());
    _ensureStockTrackedProductsCache();
    return _cachedStockTrackedProducts!;
  }

  double get totalUnitsInStock =>
      stockTrackedProducts.fold<double>(0, (sum, item) => sum + item.stock);
  double get inventoryRetailValue => stockTrackedProducts.fold<double>(
        0,
        (sum, item) => sum + (item.usdPrice * item.stock),
      );
  double get inventoryCostValue => stockTrackedProducts.fold<double>(
        0,
        (sum, item) => sum + (_safeUsdCost(item) * item.stock),
      );

  List<Product> _sortedProducts(List<Product> items) {
    final sorted = List<Product>.from(items);
    sorted.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      final codeCompare = a.code.toLowerCase().compareTo(b.code.toLowerCase());
      if (codeCompare != 0) return codeCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  Future<void> initialize() async {
    StartupTimingService.event('app_store.initialize.begin',
        category: 'app_store');
    await _migrateLegacySharedPreferencesIfNeeded();
    await _ensureDeviceId();

    final schemaVersion =
        int.tryParse(LocalDatabaseService.getString(_schemaVersionKey) ?? '') ??
            0;
    final canUseFastStartup =
        LocalDatabaseService.isSqliteAuthoritative && schemaVersion >= 17;

    if (canUseFastStartup) {
      await StartupTimingService.measure(
        'app_store.fast_startup_load',
        () async {
          // Startup performance fix: keep the first shell light.
          // Only scalar keys plus small login/catalog lists are hydrated here.
          // Core business lists load in the background after the app is ready.
          _categories
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_categoriesKey));
          _brands
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_brandsKey));
          _units
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_unitsKey));
          _storeProfile = _loadStoreProfile();
          AccountingService.configureMoneyPolicy(_storeProfile);
          _invoiceCounter = _loadInvoiceCounter();
          _purchaseCounter = _loadPurchaseCounter();
          _currentRole =
              LocalDatabaseService.getString(_currentRoleKey) ?? 'admin';
          _roles
            ..clear()
            ..addAll(_loadRoles());
          _users
            ..clear()
            ..addAll(_loadUsers());
          await _ensureDefaultAdminUser();
          _rememberLogin =
              LocalDatabaseService.getString(_rememberLoginKey) == 'true';
          _restoreActiveUser();
          _appIdentity = _loadOrCreateAppIdentity();
          _syncSequence = int.tryParse(
                LocalDatabaseService.getString(_syncSequenceKey) ?? '',
              ) ??
              0;
          _ensureCatalogDefaults();
          _rebuildMutableEntityIndexes();
        },
        category: 'app_store',
      );

      _isReady = true;
      notifyListeners();
      unawaited(_requestSyncDataLoad());
      StartupTimingService.event('app_store.ready', category: 'app_store');
      return;
    }

    _products
      ..clear()
      ..addAll(await _loadProductsForStartup());
    _customers
      ..clear()
      ..addAll(await _loadCustomersForStartup());
    _sales
      ..clear()
      ..addAll(await _loadSalesForStartup());
    _saleQuotations
      ..clear()
      ..addAll(await _loadSaleQuotationsForStartup());
    _deliveryNotes
      ..clear()
      ..addAll(await _loadDeliveryNotesForStartup());
    _billsOfMaterials
      ..clear()
      ..addAll(await _loadBillsOfMaterialsForStartup());
    _manufacturingOrders
      ..clear()
      ..addAll(await _loadManufacturingOrdersForStartup());
    _suppliers
      ..clear()
      ..addAll(await _loadSuppliersForStartup());
    _supplierProductPrices
      ..clear()
      ..addAll(await _loadSupplierProductPricesForStartup());
    _categories
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_categoriesKey));
    _brands
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_brandsKey));
    _units
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_unitsKey));
    _expenses
      ..clear()
      ..addAll(await _loadExpensesForStartup());
    _purchases
      ..clear()
      ..addAll(await _loadPurchasesForStartup());
    _stockMovements
      ..clear()
      ..addAll(_loadStockMovements());
    _inventoryCounts
      ..clear()
      ..addAll(await _loadInventoryCountsForStartup());
    _warehouses
      ..clear()
      ..addAll(await _loadWarehousesForStartup());
    _ensureDefaultWarehouse();
    _storeProfile = _loadStoreProfile();
    AccountingService.configureMoneyPolicy(_storeProfile);
    _invoiceCounter = _loadInvoiceCounter();
    _purchaseCounter = _loadPurchaseCounter();
    _currentRole = LocalDatabaseService.getString(_currentRoleKey) ?? 'admin';
    _roles
      ..clear()
      ..addAll(_loadRoles());
    _users
      ..clear()
      ..addAll(_loadUsers());
    await _ensureDefaultAdminUser();
    _rememberLogin =
        LocalDatabaseService.getString(_rememberLoginKey) == 'true';
    _restoreActiveUser();
    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();
    _normalizeCustomers();
    _ensureCatalogDefaults();
    _ensureDefaultPriceLists();
    _ensureDefaultProductPriceEntries();
    await _runDataMigrationsIfNeeded();
    _rebuildStockMovementIndexes();
    _rebuildPurchaseIndexes();
    _rebuildExpenseIndexes();
    _touchPurchasesData();
    _touchExpensesData();
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;

    _isReady = true;
    notifyListeners();
    StartupTimingService.event('app_store.ready', category: 'app_store');
  }

  Future<String?> _loadEntityListJsonForStartup(String key) {
    return LocalDatabaseService.getBusinessEntityListJson(key);
  }

  Future<List<String>> _loadEntityListJsonBatchesForStartup(
    String key, {
    int batchSize = 100,
  }) {
    return LocalDatabaseService.getBusinessEntityListJsonBatches(
      key,
      batchSize: batchSize,
    );
  }

  Future<List<T>> _decodeDeferredList<T>(
      String key, T Function(Map<String, dynamic>) fromJson,
      {int? batchSize}) async {
    return StartupTimingService.measure(
      'app_store.decode.$key',
      () async {
        if (batchSize != null && batchSize > 0) {
          final batches = await _loadEntityListJsonBatchesForStartup(
            key,
            batchSize: batchSize,
          );
          if (batches.isNotEmpty) {
            final result = <T>[];
            for (final batchRaw in batches) {
              if (batchRaw.trim().isEmpty) {
                await Future<void>.delayed(Duration.zero);
                continue;
              }
              final decoded = batchRaw.length > 250000
                  ? await compute(_decodeJsonListPayload, batchRaw)
                  : _decodeJsonListPayload(batchRaw);
              for (final item in decoded) {
                result.add(fromJson(item));
              }
              await Future<void>.delayed(Duration.zero);
            }
            return result;
          }
        }
        var raw = await _loadEntityListJsonForStartup(key);
        raw ??= LocalDatabaseService.getString(key);
        if (raw == null || raw.isEmpty) return <T>[];
        final decoded = raw.length > 250000
            ? await compute(_decodeJsonListPayload, raw)
            : _decodeJsonListPayload(raw);
        final result = <T>[];
        const chunkSize = 750;
        for (var index = 0; index < decoded.length; index += 1) {
          result.add(fromJson(decoded[index]));
          if ((index + 1) % chunkSize == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        return result;
      },
      category: 'app_store',
    );
  }

  Future<List<T>> _loadTypedOrLegacyList<T>(
    String key,
    Future<List<T>?> Function() typedLoader,
    T Function(Map<String, dynamic>) fromJson, {
    int? batchSize,
  }) async {
    final typed = await typedLoader();
    if (typed != null) return typed;
    return _decodeDeferredList<T>(
      key,
      fromJson,
      batchSize: batchSize,
    );
  }

  Future<List<StockMovement>> _loadStockMovementsForStartup() async {
    final typed = await LocalDatabaseService.getStockMovementsFromSqlite();
    if (typed != null) return typed;
    return _decodeDeferredList<StockMovement>(
      _stockMovementsKey,
      StockMovement.fromJson,
      batchSize: 100,
    );
  }

  Future<List<Product>> _loadProductsForStartup() async =>
      _loadTypedOrLegacyList<Product>(
        _productsKey,
        LocalDatabaseService.getProductsFromSqlite,
        Product.fromJson,
        batchSize: 100,
      );

  Future<List<Sale>> _loadSalesForStartup() async =>
      _loadTypedOrLegacyList<Sale>(
        _salesKey,
        LocalDatabaseService.getSalesFromSqlite,
        Sale.fromJson,
        batchSize: 100,
      );

  Future<List<SaleQuotation>> _loadSaleQuotationsForStartup() async =>
      _loadTypedOrLegacyList<SaleQuotation>(
        _saleQuotationsKey,
        LocalDatabaseService.getSaleQuotationsFromSqlite,
        SaleQuotation.fromJson,
        batchSize: 100,
      );

  Future<List<DeliveryNote>> _loadDeliveryNotesForStartup() async =>
      _loadTypedOrLegacyList<DeliveryNote>(
        _deliveryNotesKey,
        LocalDatabaseService.getDeliveryNotesFromSqlite,
        DeliveryNote.fromJson,
        batchSize: 100,
      );

  Future<List<Purchase>> _loadPurchasesForStartup() async =>
      _loadTypedOrLegacyList<Purchase>(
        _purchasesKey,
        LocalDatabaseService.getPurchasesFromSqlite,
        Purchase.fromJson,
        batchSize: 100,
      );

  Future<List<InventoryCountSession>> _loadInventoryCountsForStartup() async =>
      _loadTypedOrLegacyList<InventoryCountSession>(
        _inventoryCountsKey,
        LocalDatabaseService.getInventoryCountsFromSqlite,
        InventoryCountSession.fromJson,
        batchSize: 100,
      );

  Future<List<BillOfMaterials>> _loadBillsOfMaterialsForStartup() async =>
      _loadTypedOrLegacyList<BillOfMaterials>(
        _billsOfMaterialsKey,
        LocalDatabaseService.getBillOfMaterialsFromSqlite,
        BillOfMaterials.fromJson,
        batchSize: 100,
      );

  Future<List<ManufacturingOrder>> _loadManufacturingOrdersForStartup() async =>
      _loadTypedOrLegacyList<ManufacturingOrder>(
        _manufacturingOrdersKey,
        LocalDatabaseService.getManufacturingOrdersFromSqlite,
        ManufacturingOrder.fromJson,
        batchSize: 100,
      );

  Future<List<AccountTransaction>> _loadAccountTransactionsForStartup() async {
    final typed = await LocalDatabaseService.getAccountTransactionsFromSqlite();
    if (typed != null) return typed;
    return _decodeDeferredList<AccountTransaction>(
      _accountTransactionsKey,
      AccountTransaction.fromJson,
      batchSize: 100,
    );
  }

  Future<List<Customer>> _loadCustomersForStartup() async =>
      _loadTypedOrLegacyList<Customer>(
        _customersKey,
        LocalDatabaseService.getCustomersFromSqlite,
        Customer.fromJson,
      );

  Future<List<Supplier>> _loadSuppliersForStartup() async =>
      _loadTypedOrLegacyList<Supplier>(
        _suppliersKey,
        LocalDatabaseService.getSuppliersFromSqlite,
        Supplier.fromJson,
      );

  Future<List<Expense>> _loadExpensesForStartup() async =>
      _loadTypedOrLegacyList<Expense>(
        _expensesKey,
        LocalDatabaseService.getExpensesFromSqlite,
        Expense.fromJson,
      );

  Future<List<Warehouse>> _loadWarehousesForStartup() async =>
      _loadTypedOrLegacyList<Warehouse>(
        _warehousesKey,
        LocalDatabaseService.getWarehousesFromSqlite,
        Warehouse.fromJson,
      );

  Future<List<CatalogItem>> _loadCatalogItemsForStartup(String key) async =>
      _loadTypedOrLegacyList<CatalogItem>(
        key,
        () => LocalDatabaseService.getCatalogItemsFromSqlite(key),
        CatalogItem.fromJson,
      );

  Future<List<SupplierProductPrice>>
      _loadSupplierProductPricesForStartup() async =>
          _loadTypedOrLegacyList<SupplierProductPrice>(
            _supplierProductPricesKey,
            LocalDatabaseService.getSupplierProductPricesFromSqlite,
            SupplierProductPrice.fromJson,
          );

  Future<List<PriceList>> _loadPriceListsForStartup() async =>
      _loadTypedOrLegacyList<PriceList>(
        _priceListsKey,
        LocalDatabaseService.getPriceListsFromSqlite,
        PriceList.fromJson,
      );

  Future<List<ProductPrice>> _loadProductPricesForStartup() async =>
      _loadTypedOrLegacyList<ProductPrice>(
        _productPricesKey,
        LocalDatabaseService.getProductPricesFromSqlite,
        ProductPrice.fromJson,
      );

  Future<List<ProductPriceOverride>>
      _loadProductPriceOverridesForStartup() async =>
          _loadTypedOrLegacyList<ProductPriceOverride>(
            _productPriceOverridesKey,
            LocalDatabaseService.getProductPriceOverridesFromSqlite,
            ProductPriceOverride.fromJson,
          );

  Future<List<ProductCost>> _loadProductCostsForStartup() async =>
      _loadTypedOrLegacyList<ProductCost>(
        _productCostsKey,
        LocalDatabaseService.getProductCostsFromSqlite,
        ProductCost.fromJson,
      );

  Future<List<CostingMethodHistory>>
      _loadCostingMethodHistoryForStartup() async =>
          _loadTypedOrLegacyList<CostingMethodHistory>(
            _costingMethodHistoryKey,
            LocalDatabaseService.getCostingMethodHistoryFromSqlite,
            CostingMethodHistory.fromJson,
          );

  Future<List<InventoryCostLayer>> _loadInventoryCostLayersForStartup() async =>
      _loadTypedOrLegacyList<InventoryCostLayer>(
        _inventoryCostLayersKey,
        LocalDatabaseService.getInventoryCostLayersFromSqlite,
        InventoryCostLayer.fromJson,
      );

  // ignore: unused_element
  Future<void> _loadDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.core_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final products = await _loadProductsForStartup();
          _products
            ..clear()
            ..addAll(products);
          await Future<void>.delayed(Duration.zero);

          final customers = await _loadCustomersForStartup();
          _customers
            ..clear()
            ..addAll(customers);
          await Future<void>.delayed(Duration.zero);

          final sales = await _loadSalesForStartup();
          _sales
            ..clear()
            ..addAll(sales);
          await Future<void>.delayed(Duration.zero);

          final saleQuotations = await _loadSaleQuotationsForStartup();
          _saleQuotations
            ..clear()
            ..addAll(saleQuotations);
          await Future<void>.delayed(Duration.zero);

          final deliveryNotes = await _loadDeliveryNotesForStartup();
          _deliveryNotes
            ..clear()
            ..addAll(deliveryNotes);
          await Future<void>.delayed(Duration.zero);

          final billsOfMaterials = await _loadBillsOfMaterialsForStartup();
          _billsOfMaterials
            ..clear()
            ..addAll(billsOfMaterials);
          await Future<void>.delayed(Duration.zero);

          final manufacturingOrders =
              await _loadManufacturingOrdersForStartup();
          _manufacturingOrders
            ..clear()
            ..addAll(manufacturingOrders);
          await Future<void>.delayed(Duration.zero);

          final suppliers = await _loadSuppliersForStartup();
          _suppliers
            ..clear()
            ..addAll(suppliers);
          await Future<void>.delayed(Duration.zero);

          final supplierProductPrices =
              await _loadSupplierProductPricesForStartup();
          _supplierProductPrices
            ..clear()
            ..addAll(supplierProductPrices);
          await Future<void>.delayed(Duration.zero);

          final priceLists = await _loadPriceListsForStartup();
          _priceLists
            ..clear()
            ..addAll(priceLists);
          await Future<void>.delayed(Duration.zero);

          final productPrices = await _loadProductPricesForStartup();
          _productPrices
            ..clear()
            ..addAll(productPrices);
          await Future<void>.delayed(Duration.zero);

          final productPriceOverrides =
              await _loadProductPriceOverridesForStartup();
          _productPriceOverrides
            ..clear()
            ..addAll(productPriceOverrides);
          await Future<void>.delayed(Duration.zero);

          final productCosts = await _loadProductCostsForStartup();
          _productCosts
            ..clear()
            ..addAll(productCosts);
          _rebuildProductPricingLookupCaches();
          await Future<void>.delayed(Duration.zero);

          final costingMethodHistory =
              await _loadCostingMethodHistoryForStartup();
          _costingMethodHistory
            ..clear()
            ..addAll(costingMethodHistory);
          await Future<void>.delayed(Duration.zero);

          final inventoryCostLayers =
              await _loadInventoryCostLayersForStartup();
          _inventoryCostLayers
            ..clear()
            ..addAll(inventoryCostLayers);
          _rebuildInventoryCostLayerLookupCache();
          _inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
            LocalDatabaseService.getString(_inventoryCostingMethodKey),
          );
          await Future<void>.delayed(Duration.zero);

          final expenses = await _loadExpensesForStartup();
          _expenses
            ..clear()
            ..addAll(expenses);
          await Future<void>.delayed(Duration.zero);

          final purchases = await _loadPurchasesForStartup();
          _purchases
            ..clear()
            ..addAll(purchases);
          await Future<void>.delayed(Duration.zero);

          final stockMovements = await _loadStockMovementsForStartup();
          _stockMovements
            ..clear()
            ..addAll(stockMovements);
          await Future<void>.delayed(Duration.zero);

          final inventoryCounts = await _loadInventoryCountsForStartup();
          _inventoryCounts
            ..clear()
            ..addAll(inventoryCounts);
          await Future<void>.delayed(Duration.zero);

          final warehouses = await _loadWarehousesForStartup();
          _warehouses
            ..clear()
            ..addAll(warehouses);
          await Future<void>.delayed(Duration.zero);

          _ensureDefaultPriceLists();
          _ensureDefaultProductPriceEntries();
          _ensureProductCostEntries();
          _ensureCostingMethodHistory();
          _ensureDefaultWarehouse();

          _normalizeCustomers();
          _ensureCatalogDefaults();
          _rebuildMutableEntityIndexes();
          _touchPurchasesData();
          _touchExpensesData();
          _invoiceCounter = _loadInvoiceCounter();
          _purchaseCounter = _loadPurchaseCounter();
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Deferred startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  // ignore: unused_element
  Future<void> _loadLedgerDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.ledger_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final accountTransactions =
              await _loadAccountTransactionsForStartup();
          _accountTransactions
            ..clear()
            ..addAll(accountTransactions);
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Ledger startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _loadSyncDeferredStartupData() async {
    try {
      await StartupTimingService.measure(
        'app_store.sync_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final syncChanges = await _decodeDeferredList<SyncChange>(
            _syncChangesKey,
            SyncChange.fromJson,
            batchSize: 100,
          );
          _syncChanges
            ..clear()
            ..addAll(syncChanges);
          await Future<void>.delayed(Duration.zero);

          final syncQueue = await _decodeDeferredList<SyncQueueItem>(
            _syncQueueKey,
            SyncQueueItem.fromJson,
            batchSize: 100,
          );
          _syncQueue
            ..clear()
            ..addAll(syncQueue);
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Sync startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  /// Reloads the in-memory AppStore state after a manual Database Admin change.
  ///
  /// DatabasePage can edit the persistent local database directly. Without this
  /// refresh, screens that already cached products, identity, users, stock, or
  /// reports in AppStore keep showing old values until a full app restart.
  Future<void> refreshAfterDatabaseChange(String key) async {
    try {
      switch (key) {
        case _appIdentityKey:
          _appIdentity = _loadOrCreateAppIdentity();
          break;

        case _storeProfileKey:
          _storeProfile = _loadStoreProfile();
          AccountingService.configureMoneyPolicy(_storeProfile);
          _touchDataRevisions(storeProfile: true);
          break;

        case _productsKey:
          _products
            ..clear()
            ..addAll(await _loadProductsForStartup());
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case _customersKey:
          _customers
            ..clear()
            ..addAll(await _loadCustomersForStartup());
          _normalizeCustomers();
          _touchDataRevisions(customers: true);
          break;

        case _salesKey:
          _sales
            ..clear()
            ..addAll(await _loadSalesForStartup());
          _invoiceCounter = _loadInvoiceCounter();
          _touchDataRevisions(sales: true);
          break;

        case _saleQuotationsKey:
          _saleQuotations
            ..clear()
            ..addAll(await _loadSaleQuotationsForStartup());
          break;

        case _deliveryNotesKey:
          _deliveryNotes
            ..clear()
            ..addAll(await _loadDeliveryNotesForStartup());
          _touchDataRevisions(deliveryNotes: true);
          break;

        case _billsOfMaterialsKey:
          _billsOfMaterials
            ..clear()
            ..addAll(await _loadBillsOfMaterialsForStartup());
          break;

        case _manufacturingOrdersKey:
          _manufacturingOrders
            ..clear()
            ..addAll(await _loadManufacturingOrdersForStartup());
          break;

        case _suppliersKey:
          _suppliers
            ..clear()
            ..addAll(await _loadSuppliersForStartup());
          _touchDataRevisions(suppliers: true);
          break;

        case _supplierProductPricesKey:
          _supplierProductPrices
            ..clear()
            ..addAll(await _loadSupplierProductPricesForStartup());
          _touchDataRevisions(supplierProductPrices: true);
          break;

        case _priceListsKey:
          _priceLists
            ..clear()
            ..addAll(await _loadPriceListsForStartup());
          _ensureDefaultPriceLists();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case _productPricesKey:
          _productPrices
            ..clear()
            ..addAll(await _loadProductPricesForStartup());
          _ensureDefaultProductPriceEntries();
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case _productPriceOverridesKey:
          _productPriceOverrides
            ..clear()
            ..addAll(await _loadProductPriceOverridesForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case _productCostsKey:
          _productCosts
            ..clear()
            ..addAll(await _loadProductCostsForStartup());
          _rebuildProductPricingLookupCaches();
          _touchDataRevisions(products: true);
          break;

        case _costingMethodHistoryKey:
          _costingMethodHistory
            ..clear()
            ..addAll(await _loadCostingMethodHistoryForStartup());
          _touchDataRevisions(products: true);
          break;

        case _inventoryCostLayersKey:
          _inventoryCostLayers
            ..clear()
            ..addAll(await _loadInventoryCostLayersForStartup());
          _rebuildInventoryCostLayerLookupCache();
          _touchDataRevisions(products: true);
          break;

        case _expensesKey:
          _expenses
            ..clear()
            ..addAll(await _loadExpensesForStartup());
          _rebuildExpenseIndexes();
          _touchExpensesData();
          break;

        case _purchasesKey:
          _purchases
            ..clear()
            ..addAll(await _loadPurchasesForStartup());
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case _stockMovementsKey:
          _stockMovements
            ..clear()
            ..addAll(await _loadStockMovementsForStartup());
          _touchDataRevisions(stockMovements: true);
          break;

        case _inventoryCountsKey:
          _inventoryCounts
            ..clear()
            ..addAll(await _loadInventoryCountsForStartup());
          _touchDataRevisions(inventoryCounts: true);
          break;

        case _warehousesKey:
          _warehouses
            ..clear()
            ..addAll(await _loadWarehousesForStartup());
          _ensureDefaultWarehouse();
          _touchDataRevisions(warehouses: true);
          break;

        case _accountTransactionsKey:
          _accountTransactions
            ..clear()
            ..addAll(await _loadAccountTransactionsForStartup());
          _invalidateAccountLedgerCache();
          _touchDataRevisions(accountTransactions: true);
          break;

        case _categoriesKey:
          _categories
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_categoriesKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case _brandsKey:
          _brands
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_brandsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case _unitsKey:
          _units
            ..clear()
            ..addAll(await _loadCatalogItemsForStartup(_unitsKey));
          _ensureCatalogDefaults();
          _touchDataRevisions(products: true);
          break;

        case _rolesKey:
        case _usersKey:
        case _activeUserKey:
        case _rememberLoginKey:
          _roles
            ..clear()
            ..addAll(_loadRoles());
          _users
            ..clear()
            ..addAll(_loadUsers());
          _rememberLogin =
              LocalDatabaseService.getString(_rememberLoginKey) == 'true';
          _activeUser = null;
          _restoreActiveUser();
          break;

        case _syncChangesKey:
          _syncChanges
            ..clear()
            ..addAll(_loadSyncChanges());
          _syncSequence = _loadSyncSequence();
          break;

        case _syncQueueKey:
          _syncQueue
            ..clear()
            ..addAll(_loadSyncQueue());
          break;

        case _invoiceCounterKey:
          _invoiceCounter = _loadInvoiceCounter();
          break;

        case _purchaseCounterKey:
          _purchaseCounter = _loadPurchaseCounter();
          break;

        case _syncSequenceKey:
          _syncSequence = _loadSyncSequence();
          break;

        default:
          await reloadAllAfterDatabaseChange();
          return;
      }

      _rebuildMutableEntityIndexes();
      _rebuildProductPricingLookupCaches();
      _invalidateDerivedDataCaches();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Database admin refresh failed for $key: $error');
      debugPrint('$stackTrace');
      await reloadAllAfterDatabaseChange();
    }
  }

  /// Conservative full refresh used for unknown keys or recovery after a failed
  /// targeted refresh.
  Future<void> reloadAllAfterDatabaseChange() async {
    _appIdentity = _loadOrCreateAppIdentity();
    _storeProfile = _loadStoreProfile();
    AccountingService.configureMoneyPolicy(_storeProfile);
    _products
      ..clear()
      ..addAll(await _loadProductsForStartup());
    _customers
      ..clear()
      ..addAll(await _loadCustomersForStartup());
    _sales
      ..clear()
      ..addAll(await _loadSalesForStartup());
    _saleQuotations
      ..clear()
      ..addAll(await _loadSaleQuotationsForStartup());
    _deliveryNotes
      ..clear()
      ..addAll(await _loadDeliveryNotesForStartup());
    _billsOfMaterials
      ..clear()
      ..addAll(await _loadBillsOfMaterialsForStartup());
    _manufacturingOrders
      ..clear()
      ..addAll(await _loadManufacturingOrdersForStartup());
    _suppliers
      ..clear()
      ..addAll(await _loadSuppliersForStartup());
    _supplierProductPrices
      ..clear()
      ..addAll(await _loadSupplierProductPricesForStartup());
    _expenses
      ..clear()
      ..addAll(await _loadExpensesForStartup());
    _purchases
      ..clear()
      ..addAll(await _loadPurchasesForStartup());
    _stockMovements
      ..clear()
      ..addAll(_loadStockMovements());
    _inventoryCounts
      ..clear()
      ..addAll(await _loadInventoryCountsForStartup());
    _warehouses
      ..clear()
      ..addAll(await _loadWarehousesForStartup());
    _priceLists
      ..clear()
      ..addAll(await _loadPriceListsForStartup());
    _productPrices
      ..clear()
      ..addAll(await _loadProductPricesForStartup());
    _productPriceOverrides
      ..clear()
      ..addAll(await _loadProductPriceOverridesForStartup());
    _productCosts
      ..clear()
      ..addAll(await _loadProductCostsForStartup());
    _costingMethodHistory
      ..clear()
      ..addAll(await _loadCostingMethodHistoryForStartup());
    _inventoryCostLayers
      ..clear()
      ..addAll(await _loadInventoryCostLayersForStartup());
    _rebuildInventoryCostLayerLookupCache();
    _accountTransactions
      ..clear()
      ..addAll(await _loadAccountTransactionsForStartup());
    _categories
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_categoriesKey));
    _brands
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_brandsKey));
    _units
      ..clear()
      ..addAll(await _loadCatalogItemsForStartup(_unitsKey));
    _roles
      ..clear()
      ..addAll(_loadRoles());
    _users
      ..clear()
      ..addAll(_loadUsers());
    _syncChanges
      ..clear()
      ..addAll(_loadSyncChanges());
    _syncQueue
      ..clear()
      ..addAll(_loadSyncQueue());

    _rememberLogin =
        LocalDatabaseService.getString(_rememberLoginKey) == 'true';
    _activeUser = null;
    _restoreActiveUser();
    _normalizeCustomers();
    _ensureCatalogDefaults();
    _ensureDefaultWarehouse();
    _invoiceCounter = _loadInvoiceCounter();
    _purchaseCounter = _loadPurchaseCounter();
    _syncSequence = _loadSyncSequence();
    _rebuildMutableEntityIndexes();
    _rebuildProductPricingLookupCaches();
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      deliveryNotes: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      inventoryCounts: true,
      warehouses: true,
      accountTransactions: true,
      storeProfile: true,
    );
    _invalidateAccountLedgerCache();
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> _migrateLegacySharedPreferencesIfNeeded() async {
    if (!LocalDatabaseService.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final hasLegacyData = prefs.containsKey('products_v2') ||
        prefs.containsKey('customers_v2') ||
        prefs.containsKey('sales_v2') ||
        prefs.containsKey('products_v3') ||
        prefs.containsKey('customers_v3') ||
        prefs.containsKey('sales_v3') ||
        prefs.containsKey('suppliers_v3') ||
        prefs.containsKey('expenses_v3') ||
        prefs.containsKey('store_profile_v4');

    if (!hasLegacyData) return;

    final legacyProducts =
        prefs.getString('products_v3') ?? prefs.getString('products_v2');
    final legacyCustomers =
        prefs.getString('customers_v3') ?? prefs.getString('customers_v2');
    final legacySales =
        prefs.getString('sales_v3') ?? prefs.getString('sales_v2');
    final legacySuppliers = prefs.getString('suppliers_v3');
    final legacyExpenses = prefs.getString('expenses_v3');
    final legacyStoreProfile = prefs.getString('store_profile_v4');
    final legacyDeviceId = prefs.getString(_deviceIdKey);
    final legacySyncChanges = prefs.getString(_syncChangesKey);

    if (legacyProducts != null) {
      await LocalDatabaseService.setString(_productsKey, legacyProducts);
    }
    if (legacyCustomers != null) {
      await LocalDatabaseService.setString(_customersKey, legacyCustomers);
    }
    if (legacySales != null) {
      await LocalDatabaseService.setString(_salesKey, legacySales);
    }
    if (legacySuppliers != null) {
      await LocalDatabaseService.setString(_suppliersKey, legacySuppliers);
    }
    if (legacyExpenses != null) {
      await LocalDatabaseService.setString(_expensesKey, legacyExpenses);
    }
    if (legacyStoreProfile != null) {
      await LocalDatabaseService.setString(
        _storeProfileKey,
        legacyStoreProfile,
      );
    }
    if (legacyDeviceId != null) {
      await LocalDatabaseService.setString(_deviceIdKey, legacyDeviceId);
    }
    if (legacySyncChanges != null) {
      await LocalDatabaseService.setString(_syncChangesKey, legacySyncChanges);
    }
  }

  Future<void> _ensureDeviceId() async {
    final existing = LocalDatabaseService.getString(_deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      _deviceId = _normalizeGeneratedId(existing.trim(), fallbackPrefix: 'DV');
      if (_deviceId != existing.trim()) {
        await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
      }
      return;
    }
    _deviceId = _generatePrefixedId('DV');
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
  }

  String _generatePrefixedId(String prefix) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final body = List<String>.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '${prefix.toUpperCase()}-$body';
  }

  String _normalizeGeneratedId(String value, {required String fallbackPrefix}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return _generatePrefixedId(fallbackPrefix);
    final parts = trimmed.split('-');
    if (parts.length == 2) {
      final rawPrefix = parts.first.toUpperCase();
      final prefix = rawPrefix == 'DEV' || rawPrefix == 'Dev'.toUpperCase()
          ? 'DV'
          : rawPrefix;
      final body = parts.last.toUpperCase();
      return '$prefix-$body';
    }
    return trimmed.toUpperCase();
  }

  List<StockMovement> _loadStockMovements() {
    final raw = LocalDatabaseService.getString(_stockMovementsKey);
    if (raw == null) return <StockMovement>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  void _ensureCatalogDefaults() {
    if (_categories.isEmpty) {
      _categories.add(
        CatalogItem(
          id: 'cat_general',
          nameEn: 'General',
          nameAr: 'عام',
          code: 'General',
        ),
      );
    }
    if (_brands.isEmpty) {
      _brands.add(
        CatalogItem(
          id: 'brand_generic',
          nameEn: 'Generic',
          nameAr: 'عام',
          code: 'Generic',
        ),
      );
    }
    if (_units.isEmpty) {
      _units.addAll([
        CatalogItem(
          id: 'unit_pcs',
          nameEn: 'Piece',
          nameAr: 'قطعة',
          code: 'pcs',
        ),
        CatalogItem(id: 'unit_box', nameEn: 'Box', nameAr: 'علبة', code: 'box'),
        CatalogItem(
          id: 'unit_pack',
          nameEn: 'Pack',
          nameAr: 'باكيت',
          code: 'pack',
        ),
        CatalogItem(
          id: 'unit_kg',
          nameEn: 'Kilogram',
          nameAr: 'كيلوغرام',
          code: 'kg',
        ),
        CatalogItem(id: 'unit_g', nameEn: 'Gram', nameAr: 'غرام', code: 'g'),
        CatalogItem(id: 'unit_l', nameEn: 'Liter', nameAr: 'ليتر', code: 'L'),
        CatalogItem(
          id: 'unit_ml',
          nameEn: 'Milliliter',
          nameAr: 'ميليلتر',
          code: 'ml',
        ),
        CatalogItem(id: 'unit_m', nameEn: 'Meter', nameAr: 'متر', code: 'm'),
      ]);
    }
    _seedCatalogFromProducts(
      _categories,
      _products.map((item) => item.category),
    );
    _seedCatalogFromProducts(_brands, _products.map((item) => item.brand));
    _seedCatalogFromProducts(_units, _products.map((item) => item.unit));
  }

  void _seedCatalogFromProducts(
    List<CatalogItem> target,
    Iterable<String> values,
  ) {
    final used = target.map((item) => item.nameEn.trim().toLowerCase()).toSet();
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty || used.contains(value.toLowerCase())) continue;
      target.add(
        CatalogItem(
          id: DateTime.now().microsecondsSinceEpoch.toString() +
              target.length.toString(),
          nameEn: value,
          nameAr: '',
          code: value,
        ),
      );
      used.add(value.toLowerCase());
    }
  }

  List<SyncChange> _loadSyncChanges() {
    final raw = LocalDatabaseService.getString(_syncChangesKey);
    if (raw == null) return <SyncChange>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  int _loadSyncSequence() {
    final stored =
        int.tryParse(LocalDatabaseService.getString(_syncSequenceKey) ?? '') ??
            0;
    final highest = _syncChanges.fold<int>(
      0,
      (value, change) => change.sequence > value ? change.sequence : value,
    );
    return stored > highest ? stored : highest;
  }

  int _nextSyncSequence() {
    _syncSequence += 1;
    return _syncSequence;
  }

  String _newSyncEnvelopeId(DateTime now, String prefix) {
    final safeDevice = _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${safeDevice}_${now.microsecondsSinceEpoch}_${_syncChanges.length}_$_syncSequence';
  }

  Map<String, dynamic> _syncV2MetaOf(SyncChange change) {
    return Map<String, dynamic>.from(
      change.payload['_syncV2'] as Map? ?? const {},
    );
  }

  String _syncMetaString(SyncChange change, String key) {
    final value = _syncV2MetaOf(change)[key];
    return value == null ? '' : value.toString();
  }

  bool _isReplayOrDuplicateSyncEvent(
    SyncChange change, {
    required Set<String> existingEnvelopeIds,
    required Set<String> existingEventIds,
    required Set<String> acceptedSourceCommandIds,
    required int lastAppliedSequence,
  }) {
    if (existingEnvelopeIds.contains(change.id)) return true;

    final meta = _syncV2MetaOf(change);
    final eventId = (meta['eventId'] ?? '').toString();
    if (eventId.isNotEmpty && existingEventIds.contains(eventId)) return true;

    final sourceCommandId = (meta['sourceCommandId'] ?? '').toString();
    if (sourceCommandId.isNotEmpty &&
        acceptedSourceCommandIds.contains(sourceCommandId)) {
      return true;
    }

    // Host sequence is the authoritative ordering guard. If this device has
    // already applied a newer/equal Host sequence, the incoming event is a
    // replay from an old cursor/page and must not be applied again.
    if (change.sequence > 0 &&
        lastAppliedSequence > 0 &&
        change.sequence <= lastAppliedSequence) {
      return true;
    }

    return false;
  }

  String? validateClientDraftForHostAcceptance(SyncChange change) {
    if (change.entityType == 'system' &&
        change.operation == 'reset_store_data') {
      return 'Reset data can only be initiated on the Host device.';
    }
    if (change.operation == 'delete') return null;
    final p = change.payload;
    switch (change.entityType) {
      case 'product':
        final code = (p['code'] ?? '').toString().trim().toLowerCase();
        final barcode = (p['barcode'] ?? '').toString().trim().toLowerCase();
        if (code.isEmpty) return null;
        final duplicate = _products.any((item) {
          if (item.id == change.entityId || item.isDeleted) return false;
          final sameCode = item.code.trim().toLowerCase() == code;
          final sameBarcode = barcode.isNotEmpty &&
              item.barcode.trim().toLowerCase() == barcode;
          return sameCode || sameBarcode;
        });
        if (duplicate) {
          return 'Product code or barcode already exists on the Host.';
        }
        return null;
      case 'sale':
        final invoiceNo = (p['invoiceNo'] ?? p['invoice_no'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (invoiceNo.isEmpty) return null;
        final duplicate = _sales.any(
          (item) =>
              item.id != change.entityId &&
              !item.isDeleted &&
              item.invoiceNo.trim().toLowerCase() == invoiceNo,
        );
        if (duplicate) return 'Invoice number already exists on the Host.';
        return null;
    }
    return null;
  }

  Future<void> clearPendingSyncQueue({bool notify = true}) async {
    _syncQueue.clear();
    await _saveSyncStateOnly();
    if (notify) notifyListeners();
  }

  List<SyncQueueItem> _loadSyncQueue() {
    final raw = LocalDatabaseService.getString(_syncQueueKey);
    if (raw == null) return <SyncQueueItem>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              SyncQueueItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  int _loadInvoiceCounter() {
    final raw = LocalDatabaseService.getString(_invoiceCounterKey);
    final stored = int.tryParse(raw ?? '') ?? 0;
    final highestInvoiceNo = _sales.fold<int>(0, (highest, sale) {
      final invoiceNumber = _invoiceSequenceFromNo(sale.invoiceNo);
      return invoiceNumber > highest ? invoiceNumber : highest;
    });
    return stored > highestInvoiceNo ? stored : highestInvoiceNo;
  }

  Future<void> _runDataMigrationsIfNeeded() async {
    final current =
        int.tryParse(LocalDatabaseService.getString(_schemaVersionKey) ?? '') ??
            0;
    if (current >= 17) return;

    if (current < 7) {
      // Version 7 captures unit cost on every historical sale item when possible
      // and initializes a durable invoice counter.
      for (var saleIndex = 0; saleIndex < _sales.length; saleIndex++) {
        final sale = _sales[saleIndex];
        final migratedItems = sale.items.map((item) {
          if (item.unitCost > 0) return item;
          final product = _findProductById(item.productId);
          return SaleItem(
            productId: item.productId,
            productName: item.productName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            unitName: item.unitName,
            baseQuantity: item.effectiveBaseQuantity,
            conversionToBase: item.conversionToBase,
            unitCost: product?.usdCost ?? 0,
          );
        }).toList();
        _sales[saleIndex] = Sale(
          id: sale.id,
          invoiceNo: sale.invoiceNo,
          customerName: sale.customerName,
          date: sale.date,
          status: sale.status,
          items: migratedItems,
          discount: sale.discount,
        );
      }
    }

    if (current < 8) {
      _normalizeProductCodes();
    }

    if (current < 9) {
      _prepareExistingDataForSync();
    }

    if (current < 11) {
      _prepareExistingDataForSync();
    }

    if (current < 13) {
      _normalizeProductCostReferences();
    }

    if (current < 14 && _supplierProductPrices.isEmpty) {
      _seedSupplierProductPricesFromPurchaseHistory();
    }

    if (current < 15) {
      _seedSupplierProductPricesFromLegacyProductSuppliers(
        recordSyncChanges: true,
      );
    }

    if (current < 15 &&
        LocalDatabaseService.getString(_supplierProductPricesKey) == null) {
      await LocalDatabaseService.setString(
        _supplierProductPricesKey,
        jsonEncode(
          _supplierProductPrices.map((item) => item.toJson()).toList(),
        ),
      );
    }

    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();

    await LocalDatabaseService.setString(
      _syncSequenceKey,
      _syncSequence.toString(),
    );
    await LocalDatabaseService.setString(_schemaVersionKey, '17');
    await LocalDatabaseService.setString(
      _invoiceCounterKey,
      _invoiceCounter.toString(),
    );
    await LocalDatabaseService.setString(
      _purchaseCounterKey,
      _purchaseCounter.toString(),
    );
    await _saveAll();
  }

  double _safeUsdCost(Product product) {
    final usdCost = product.usdCost.isFinite && product.usdCost >= 0
        ? product.usdCost
        : 0.0;
    final originalCost =
        product.originalCost.isFinite && product.originalCost >= 0
            ? product.originalCost
            : 0.0;
    final rawCost =
        product.cost.isFinite && product.cost >= 0 ? product.cost : 0.0;
    if (product.costCurrency.toUpperCase() != 'LBP') {
      return usdCost;
    }

    final sourceLbpCost =
        originalCost > 0 ? originalCost : (rawCost > 0 ? rawCost : usdCost);
    final expectedUsdCost = toUsdReferencePrice(
      sourceLbpCost,
      'LBP',
      storeProfile,
    );
    if (expectedUsdCost <= 0) return usdCost;

    // Legacy records sometimes stored the LBP cost directly in usdCost/cost.
    // When costCurrency is LBP, the USD reference must be originalCost / rate.
    final usdLooksLikeLbp = usdCost > expectedUsdCost * 10 || usdCost > 1000;
    return usdLooksLikeLbp ? expectedUsdCost : usdCost;
  }

  void _normalizeProductCostReferences() {
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      final normalizedUsdCost = _safeUsdCost(product);
      if ((normalizedUsdCost - product.usdCost).abs() < 0.000001 &&
          (normalizedUsdCost - product.cost).abs() < 0.000001) {
        continue;
      }
      _products[index] = product.copyWith(
        cost: normalizedUsdCost,
        usdCost: normalizedUsdCost,
      );
    }
  }

  void _prepareExistingDataForSync() {
    final now = DateTime.now();
    for (var index = 0; index < _products.length; index++) {
      final item = _products[index];
      _products[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _customers.length; index++) {
      final item = _customers[index];
      _customers[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _sales.length; index++) {
      final item = _sales[index];
      _sales[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0
            ? item.date
            : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _suppliers.length; index++) {
      final item = _suppliers[index];
      _suppliers[index] = item.copyWith(
        createdAt:
            item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _categories.length; index++) {
      _categories[index] = _prepareCatalogItemForSync(_categories[index], now);
    }
    for (var index = 0; index < _brands.length; index++) {
      _brands[index] = _prepareCatalogItemForSync(_brands[index], now);
    }
    for (var index = 0; index < _units.length; index++) {
      _units[index] = _prepareCatalogItemForSync(_units[index], now);
    }
    for (var index = 0; index < _expenses.length; index++) {
      final item = _expenses[index];
      _expenses[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0
            ? item.date
            : item.createdAt,
        updatedAt:
            item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
            ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
            : item.lastModifiedByDeviceId,
      );
    }
  }

  CatalogItem _prepareCatalogItemForSync(CatalogItem item, DateTime now) {
    return item.copyWith(
      createdAt:
          item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
      updatedAt:
          item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
      deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
      syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
      storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
      branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
      version: item.version <= 0 ? 1 : item.version,
      lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty
          ? (item.deviceId.isEmpty ? _deviceId : item.deviceId)
          : item.lastModifiedByDeviceId,
    );
  }

  void _normalizeProductCodes() {
    // Legacy migration hook: never auto-renumber duplicate product codes.
    // Product ID remains the identity; duplicate code/barcode conflicts are detected
    // and displayed for manual review instead of silently changing business data.
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      final trimmedCode = product.code.trim();
      if (trimmedCode != product.code) {
        _products[index] = product.copyWith(code: trimmedCode);
      }
    }
  }

  AppPlatformType _detectPlatform() {
    if (kIsWeb) return AppPlatformType.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return AppPlatformType.windows;
      case TargetPlatform.android:
        return AppPlatformType.android;
      default:
        return AppPlatformType.unknown;
    }
  }

  AppIdentity _loadOrCreateAppIdentity() {
    final raw = LocalDatabaseService.getString(_appIdentityKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final parsed = AppIdentity.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        final token = parsed.deviceToken.trim().isNotEmpty
            ? parsed.deviceToken.trim()
            : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}';
        final normalized = parsed.copyWith(
          deviceId: _deviceId,
          platform: _detectPlatform(),
          deviceToken: token,
          deviceName: parsed.deviceName.trim().isNotEmpty
              ? parsed.deviceName.trim()
              : _deviceId,
        );
        unawaited(
          LocalDatabaseService.setString(
            _appIdentityKey,
            jsonEncode(normalized.toJson()),
          ),
        );
        return normalized;
      } catch (_) {}
    }
    final created = AppIdentity.defaults(
      deviceId: _deviceId,
      platform: _detectPlatform(),
      detectedDeviceName: _detectInitialDeviceName(),
    );
    unawaited(
      LocalDatabaseService.setString(
        _appIdentityKey,
        jsonEncode(created.toJson()),
      ),
    );
    return created;
  }

  String _detectInitialDeviceName() {
    // Keep this conservative and dependency-free. When a platform-specific real
    // device name provider is added later, return it here. Until then, defaults
    // fall back to the stable Ventio deviceId instead of the legacy "Main device".
    return '';
  }

  Future<void> updateDeviceName(String deviceName) async {
    requirePermission(AppPermission.settingsManage);
    final cleanName = deviceName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty) {
      throw ArgumentError('Device name cannot be empty.');
    }
    if (cleanName.length > 60) {
      throw ArgumentError('Device name must be 60 characters or fewer.');
    }
    final current = appIdentity;
    if (current.deviceName == cleanName) return;
    final normalized = _normalizedLocalIdentity(
      current.copyWith(deviceName: cleanName),
    );
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
    _recordSyncChange(
      entityType: 'app_identity',
      entityId: _deviceId,
      operation: 'update',
      payload: normalized.toJson(),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> recoverExistingStoreIdentity({
    required String storeId,
    String recoveryKey = '',
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? cloudTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (!cleanStoreId.startsWith('ST-')) {
      throw ArgumentError('A valid Store ID is required.');
    }
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty)
        ? appIdentity.branchId
        : branchId.trim().toUpperCase();
    final nextRole = deviceRole ?? appIdentity.deviceRole;
    final recoveredIdentity = appIdentity.copyWith(
      storeId: cleanStoreId,
      branchId: cleanBranchId,
      recoveryKey:
          cleanRecoveryKey.isEmpty ? appIdentity.recoveryKey : cleanRecoveryKey,
      hostDeviceId: hostDeviceId ??
          (nextRole == DeviceRole.host ? _deviceId : appIdentity.hostDeviceId),
      deviceToken: (deviceToken == null || deviceToken.trim().isEmpty)
          ? appIdentity.deviceToken
          : deviceToken.trim(),
      cloudTenantId: (cloudTenantId == null || cloudTenantId.trim().isEmpty)
          ? appIdentity.cloudTenantId
          : cloudTenantId.trim(),
      deviceRole: nextRole,
      syncMode: syncMode ?? appIdentity.syncMode,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      updatedAt: DateTime.now(),
    );
    _assertLanCloudRoleRules(recoveredIdentity, source: 'store recovery');
    _appIdentity = recoveredIdentity;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    notifyListeners();
  }

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) {
    final local = appIdentity;
    if (local.isHost) {
      return local.copyWith(
        deviceId: _deviceId,
        platform: _detectPlatform(),
        updatedAt: DateTime.now(),
      );
    }
    if (decoded['appIdentity'] is! Map) {
      return local.copyWith(deviceId: _deviceId, platform: _detectPlatform());
    }
    final remote = AppIdentity.fromJson(
      Map<String, dynamic>.from(decoded['appIdentity'] as Map),
    );
    return local.copyWith(
      storeId: remote.storeId.isNotEmpty ? remote.storeId : local.storeId,
      branchId: remote.branchId.isNotEmpty ? remote.branchId : local.branchId,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      deviceRole: DeviceRole.client,
      appRole: remote.appRole,
      syncMode: local.syncMode == SyncMode.localOnly
          ? SyncMode.lanOnly
          : local.syncMode,
      hostDeviceId:
          remote.deviceId.isNotEmpty ? remote.deviceId : local.hostDeviceId,
      cloudTenantId: remote.cloudTenantId.isNotEmpty
          ? remote.cloudTenantId
          : local.cloudTenantId,
      deviceToken: local.deviceToken.trim().isNotEmpty
          ? local.deviceToken
          : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}',
      updatedAt: DateTime.now(),
    );
  }

  AppIdentity _normalizedLocalIdentity(AppIdentity identity) {
    final token = identity.deviceToken.trim().isNotEmpty
        ? identity.deviceToken.trim()
        : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}';
    return identity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
      deviceToken: token,
      updatedAt: DateTime.now(),
    );
  }

  bool _isApprovedHostTransferTarget() {
    final approvedDeviceId = LocalDatabaseService.getString(
          _hostTransferApprovedDeviceKey,
        )?.trim() ??
        '';
    return approvedDeviceId.isNotEmpty && approvedDeviceId == _deviceId;
  }

  String get approvedHostTransferDeviceId =>
      LocalDatabaseService.getString(_hostTransferApprovedDeviceKey)?.trim() ??
      '';

  Map<String, dynamic>? get pendingHostTransferRequest {
    final raw =
        LocalDatabaseService.getString(_hostTransferRequestKey)?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? get latestHostTransferNotification {
    final raw =
        LocalDatabaseService.getString(_hostTransferNotificationKey)?.trim() ??
            '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> clearHostTransferNotification() async {
    await LocalDatabaseService.setString(_hostTransferNotificationKey, '');
    notifyListeners();
  }

  Future<void> _storeHostTransferNotification(
    Map<String, dynamic> payload,
  ) async {
    await LocalDatabaseService.setString(
      _hostTransferNotificationKey,
      jsonEncode(payload),
    );
  }

  Future<void> clearLocalHostTransferRequest() async {
    await LocalDatabaseService.setString(_hostTransferRequestKey, '');
    notifyListeners();
  }

  Future<void> _forceApplyRoleFromTransfer(AppIdentity next) async {
    final normalized = _normalizedLocalIdentity(next);
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
  }

  void _assertSafeRoleTransition(
    AppIdentity next, {
    required String source,
    bool allowApprovedTransfer = false,
    bool allowInitialHostRegistration = false,
  }) {
    final current = _appIdentity;
    if (current == null) return;
    if (current.deviceRole == next.deviceRole) return;

    // Fix #4: backup, restore, pairing, rebuild, and snapshot import flows must
    // never silently convert a Host into a Client. Host role changes are only
    // allowed through the official Transfer Host flow.
    if (current.isHost && next.isClient) {
      throw StateError(
        'Host devices cannot be converted to Clients by $source. Use Transfer Host instead.',
      );
    }

    // A Client can become Host only after an explicit Host transfer approval.
    if (current.isClient &&
        next.isHost &&
        !allowInitialHostRegistration &&
        !(allowApprovedTransfer && _isApprovedHostTransferTarget())) {
      throw StateError(
        'Client devices cannot become Host by $source. Request and approve Transfer Host first.',
      );
    }
  }

  void _assertLanCloudRoleRules(AppIdentity next, {required String source}) {
    final platform = next.platform == AppPlatformType.unknown
        ? _detectPlatform()
        : next.platform;

    // Fix #9: Web devices must never be authoritative Hosts because browsers
    // cannot reliably run the local Host API/server and should not own Host
    // authority for Cloud either.
    if (platform == AppPlatformType.web && next.isHost) {
      throw StateError(
        'Web devices cannot operate as Host. Use a desktop or native mobile Host device.',
      );
    }

    final lanHost = _isLanHostConfigured;
    final lanClient = _isLanClientConfigured;
    final cloudHost = next.isHost &&
        (next.syncMode == SyncMode.cloudConnected ||
            next.syncMode == SyncMode.marketplaceEnabled);
    final cloudClient = next.isClient &&
        (next.syncMode == SyncMode.cloudConnected ||
            next.syncMode == SyncMode.marketplaceEnabled);
    final lanIdentityClient =
        next.isClient && next.syncMode == SyncMode.lanOnly;

    // A Host may be LAN Host, Cloud Host, or both. It must not simultaneously
    // carry LAN Client state from an old pairing.
    if (next.isHost && lanClient) {
      throw StateError(
        'A Host device cannot keep LAN Client state. Clear local data or use Transfer Host before changing sync role.',
      );
    }

    // A Client may configure both LAN and Cloud transport settings, but only
    // one active transport may run at a time. Sync progress is tracked by
    // deviceId/storeId/branchId, not by the transport that delivered it.
    if (next.isClient && lanClient && cloudClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'cloud') {
        throw StateError(
          'Client has LAN and Cloud configured but no active sync transport was selected.',
        );
      }
    }
    if (lanIdentityClient && cloudClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'cloud') {
        throw StateError(
          'Client has LAN and Cloud configured but no active sync transport was selected.',
        );
      }
    }

    // Prevent cross-authority conflicts: Host in one system, Client in another.
    if (lanHost && cloudClient) {
      throw StateError(
        'LAN Host + Cloud Client is not allowed by $source. Host devices cannot be Clients in another sync system.',
      );
    }
    if (cloudHost && lanClient) {
      throw StateError(
        'Cloud Host + LAN Client is not allowed by $source. Host devices cannot be Clients in another sync system.',
      );
    }
  }

  Future<void> updateAppIdentityDuringSetup(AppIdentity identity) async {
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: 'setup/pairing/rebuild');
    _assertLanCloudRoleRules(normalized, source: 'setup/pairing/rebuild');
    _appIdentity = normalized;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(normalized.toJson()),
    );
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

  Future<void> updateAppIdentity(AppIdentity identity) async {
    requirePermission(AppPermission.settingsManage);
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: 'settings update');
    _assertLanCloudRoleRules(normalized, source: 'settings update');
    final previousJson = jsonEncode(appIdentity.toJson());
    final nextJson = jsonEncode(normalized.toJson());
    if (previousJson == nextJson) return;
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, nextJson);
    _recordSyncChange(
      entityType: 'app_identity',
      entityId: _deviceId,
      operation: 'update',
      payload: normalized.toJson(),
    );
    await _saveSyncStateOnly();
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

  Future<void> updateAppIdentityLocalOnly(
    AppIdentity identity, {
    String source = 'local sync settings',
  }) async {
    requirePermission(AppPermission.settingsManage);
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: source);
    _assertLanCloudRoleRules(normalized, source: source);
    final previousJson = jsonEncode(appIdentity.toJson());
    final nextJson = jsonEncode(normalized.toJson());
    if (previousJson == nextJson) return;
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, nextJson);
    await SyncDeviceStateStore.setActiveTransport(
      normalized,
      normalized.activeSyncTransportNormalized,
    );
    notifyListeners();
  }

  Future<void> setActiveSyncTransport(String transport) async {
    requirePermission(AppPermission.settingsManage);
    final normalizedTransport = transport.trim().toLowerCase();
    if (normalizedTransport != 'lan' && normalizedTransport != 'cloud') {
      throw ArgumentError('Active sync transport must be either lan or cloud.');
    }
    final identity = appIdentity;
    if (!identity.isClient) {
      throw StateError(
        'Only Client devices switch the active sync transport. Hosts may run LAN and Cloud together.',
      );
    }
    if (normalizedTransport == 'lan' && !_isLanClientConfigured) {
      throw StateError(
        'LAN is configured only when this device has a saved Client pairing. Configure LAN before switching to it.',
      );
    }
    if (normalizedTransport == 'cloud' && !_isCloudClientConfigured) {
      throw StateError(
        'Cloud is configured only when this device has saved Cloud credentials. Configure Cloud before switching to it.',
      );
    }

    final nextIdentity = identity.copyWith(
      syncMode: normalizedTransport == 'lan'
          ? SyncMode.lanOnly
          : SyncMode.cloudConnected,
      activeSyncTransport: normalizedTransport,
      updatedAt: DateTime.now(),
    );
    _assertLanCloudRoleRules(nextIdentity, source: 'active transport switch');
    _appIdentity = nextIdentity;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(nextIdentity.toJson()),
    );
    await SyncDeviceStateStore.setActiveTransport(
      nextIdentity,
      normalizedTransport,
    );
    await _retargetPendingClientSyncQueue(normalizedTransport);
    notifyListeners();
  }

  Future<void> _retargetPendingClientSyncQueue(String activeTransport) async {
    final newTarget = activeTransport == 'lan' ? 'host' : 'cloud_host';
    final oldTarget = activeTransport == 'lan' ? 'cloud_host' : 'host';
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.target == oldTarget && item.isPending) {
        _syncQueue[i] = item.copyWith(
          id: '${item.changeId}-$newTarget',
          target: newTarget,
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (changed) await _saveSyncStateOnly();
  }

  Future<void> requestHostTransfer({String reason = ''}) async {
    if (!appIdentity.isClient) {
      throw StateError('Only a Client device can request Host transfer.');
    }
    final payload = <String, dynamic>{
      'requestingDeviceId': _deviceId,
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'hostDeviceId': appIdentity.hostDeviceId,
      'reason': reason.trim(),
      'requestedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await LocalDatabaseService.setString(
      _hostTransferRequestKey,
      jsonEncode(payload),
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'request',
      payload: payload,
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> approveHostTransfer(String requestingDeviceId) async {
    requirePermission(AppPermission.syncManage);
    final cleanDeviceId = requestingDeviceId.trim();
    if (!appIdentity.isHost) {
      throw StateError('Only the current Host can approve Host transfer.');
    }
    if (cleanDeviceId.isEmpty || cleanDeviceId == _deviceId) {
      throw ArgumentError('A valid requesting Client Device ID is required.');
    }
    await LocalDatabaseService.setString(
      _hostTransferApprovedDeviceKey,
      cleanDeviceId,
    );
    final transferPayload = <String, dynamic>{
      'approvedDeviceId': cleanDeviceId,
      'approvedByHostDeviceId': _deviceId,
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'approvedAt': DateTime.now().toIso8601String(),
    };
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: cleanDeviceId,
      operation: 'approve',
      payload: transferPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: cleanDeviceId,
      operation: 'host_transfer_approved_pending_activation',
      payload: {...transferPayload, 'status': 'approved_pending_activation'},
    );

    // The current Host must remain authoritative after approval. The device
    // requesting the transfer becomes Host only after explicit activation, then
    // publishes HOST_CHANGED. This prevents any period with no Host.
    await LocalDatabaseService.setString(
      _hostTransferRequestKey,
      jsonEncode({
        ...transferPayload,
        'requestingDeviceId': cleanDeviceId,
        'status': 'approved_pending_activation',
      }),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> activateApprovedHostTransfer() async {
    if (!appIdentity.isClient) {
      throw StateError(
        'Only a Client device can activate an approved Host transfer.',
      );
    }
    if (!_isApprovedHostTransferTarget()) {
      throw StateError('No approved Host transfer was found for this device.');
    }
    final oldHostDeviceId = appIdentity.hostDeviceId;
    final next = _normalizedLocalIdentity(
      appIdentity.copyWith(
        deviceRole: DeviceRole.host,
        hostDeviceId: '',
        updatedAt: DateTime.now(),
      ),
    );
    _assertSafeRoleTransition(
      next,
      source: 'approved Host transfer',
      allowApprovedTransfer: true,
    );
    _assertLanCloudRoleRules(next, source: 'approved Host transfer');
    _appIdentity = next;
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(next.toJson()),
    );
    await LocalDatabaseService.setString(_hostTransferApprovedDeviceKey, '');
    final activationPayload = <String, dynamic>{
      'newHostDeviceId': _deviceId,
      'oldHostDeviceId': oldHostDeviceId,
      'storeId': next.storeId,
      'branchId': next.branchId,
      'activatedAt': DateTime.now().toIso8601String(),
    };
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'activate',
      payload: activationPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'new_host_activated',
      payload: activationPayload,
    );
    _recordSyncChange(
      entityType: 'host_transfer',
      entityId: _deviceId,
      operation: 'HOST_CHANGED',
      payload: activationPayload,
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  @Deprecated('Use users and roles instead. Kept for old code compatibility.')
  Future<void> setCurrentRole(String role) async {
    throw StateError('Roles must be assigned through Users & Permissions.');
  }

  List<UserRole> _loadRoles() {
    final raw = LocalDatabaseService.getString(_rolesKey);
    if (raw == null || raw.isEmpty) return <UserRole>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  List<AppUser> _loadUsers() {
    final raw = LocalDatabaseService.getString(_usersKey);
    if (raw == null || raw.isEmpty) return <AppUser>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> _saveRolesAndUsers() async {
    await LocalDatabaseService.setString(
      _rolesKey,
      jsonEncode(_roles.map((item) => item.toJson()).toList()),
    );
    await LocalDatabaseService.setString(
      _usersKey,
      jsonEncode(_users.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _ensureDefaultAdminUser() async {
    final now = DateTime.now();
    final existingAdminRole = _roles.indexWhere((role) => role.id == 'admin');
    if (existingAdminRole == -1) {
      _roles.add(
        UserRole(
          id: 'admin',
          name: 'Admin',
          permissions: Set<String>.from(AppPermission.all),
          isSystem: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      _roles[existingAdminRole] = _roles[existingAdminRole].copyWith(
        name: 'Admin',
        permissions: Set<String>.from(AppPermission.all),
        isSystem: true,
        updatedAt: now,
      );
    }
    // Do not create a default admin account/password. A first-time install
    // must create its initial administrator from the login setup screen.
    await _saveRolesAndUsers();
  }

  void _restoreActiveUser() {
    if (isSuspendedByHost) {
      _activeUser = null;
      _rememberLogin = false;
      return;
    }
    if (!_rememberLogin) {
      _activeUser = null;
      return;
    }
    final activeId = LocalDatabaseService.getString(_activeUserKey);
    if (activeId == null || activeId.isEmpty) return;
    for (final user in _users) {
      if (user.id == activeId && user.isActive) {
        _activeUser = user;
        return;
      }
    }
  }

  Future<bool> login(
    String username,
    String password, {
    bool remember = false,
  }) async {
    if (isSuspendedByHost) return false;
    final normalized = username.trim().toLowerCase();
    final activeMatches = _users
        .where(
          (user) =>
              user.username.trim().toLowerCase() == normalized && user.isActive,
        )
        .toList();
    if (activeMatches.length > 1) {
      // Security conflict: never guess which duplicated username should log in.
      unawaited(
        AppLogger.warning(
          area: 'login',
          action: 'login_conflict',
          message: 'Duplicate active username prevented login.',
          details: 'username=$normalized count=${activeMatches.length}',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
      return false;
    }
    for (var index = 0; index < _users.length; index++) {
      final user = _users[index];
      if (user.username.trim().toLowerCase() != normalized || !user.isActive) {
        continue;
      }
      if (!await _verifyPasswordAsync(password, user.passwordHash)) {
        unawaited(
          AppLogger.warning(
            area: 'login',
            action: 'login_failed',
            message: 'Invalid credentials.',
            details: 'username=$normalized',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            devicePlatform: appIdentity.platform.name,
            deviceModel: appIdentity.deviceName.isNotEmpty
                ? appIdentity.deviceName
                : _deviceId,
            isImportant: true,
          ),
        );
        return false;
      }
      final updated = user.copyWith(lastLoginAt: DateTime.now());
      _users[index] = updated;
      _activeUser = updated;
      _rememberLogin = remember;
      notifyListeners();
      unawaited(
        LocalDatabaseService.setString(
          _rememberLoginKey,
          remember ? 'true' : 'false',
        ),
      );
      unawaited(
        LocalDatabaseService.setString(
          _activeUserKey,
          remember ? updated.id : '',
        ),
      );
      unawaited(_saveRolesAndUsers());
      unawaited(
        AppLogger.info(
          area: 'login',
          action: 'login_success',
          message: 'User logged in successfully.',
          details:
              'userId=${updated.id} username=${updated.username} remember=$remember',
          userId: updated.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
      return true;
    }
    unawaited(
      AppLogger.warning(
        area: 'login',
        action: 'login_failed',
        message: 'User not found or inactive.',
        details: 'username=$normalized',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    return false;
  }

  Future<void> logout() async {
    final user = _activeUser;
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.setString(_activeUserKey, '');
    await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    unawaited(
      AppLogger.info(
        area: 'login',
        action: 'logout',
        message: 'User logged out.',
        details:
            user == null ? '' : 'userId=${user.id} username=${user.username}',
        userId: user?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<bool> verifyAdminPassword(String password) async {
    final user = _activeUser;
    if (user == null || !isAdmin) return false;
    return _verifyPasswordAsync(password, user.passwordHash);
  }

  Future<bool> _verifyPasswordAsync(String password, String storedHash) async {
    if (storedHash.startsWith(_passwordHashPrefix)) {
      return compute(_verifyPasswordInBackground, <String, String>{
        'password': password.trim(),
        'storedHash': storedHash,
      });
    }
    return _verifyPassword(password, storedHash);
  }

  bool _verifyPassword(String password, String storedHash) {
    final cleaned = password.trim();
    if (storedHash.startsWith(_passwordHashPrefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 100000) return false;
      return storedHash ==
          _hashPasswordWithSalt(cleaned, parts[2], iterations: iterations);
    }

    // Backward compatibility for accounts created before the password hash
    // upgrade. Password changes and first-run setup now write PBKDF2 hashes.
    if (storedHash.startsWith(_legacyLocalCredentialHashPrefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 3) return false;
      return storedHash ==
          _hashLegacyLocalCredentialWithSalt(cleaned, parts[1]);
    }
    return false;
  }

  Future<void> addOrUpdateRole(UserRole role) async {
    requirePermission(AppPermission.rolesManage);
    if (role.name.trim().isEmpty) throw ArgumentError('Role name is required.');
    if (role.id == 'admin') {
      throw StateError('The built-in Admin role cannot be edited.');
    }
    final now = DateTime.now();
    final id =
        role.id.trim().isEmpty ? 'role_${now.microsecondsSinceEpoch}' : role.id;
    final saved = UserRole(
      id: id,
      name: role.name.trim(),
      permissions: role.permissions.intersection(
        Set<String>.from(AppPermission.all),
      ),
      isSystem: false,
      createdAt: role.createdAt ?? now,
      updatedAt: now,
    );
    final index = _roles.indexWhere((item) => item.id == id);
    if (index == -1) {
      _roles.add(saved);
    } else {
      if (_roles[index].isSystem) {
        throw StateError('System roles cannot be edited.');
      }
      _roles[index] = saved;
    }
    _recordSyncChange(
      entityType: 'role',
      entityId: saved.id,
      operation: index == -1 ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> deleteRole(String id) async {
    requirePermission(AppPermission.rolesManage);
    if (id == 'admin') throw StateError('The Admin role cannot be deleted.');
    if (_users.any((user) => user.roleId == id)) {
      throw StateError('Move users to another role before deleting this role.');
    }
    final removed = _roles.firstWhere(
      (role) => role.id == id && !role.isSystem,
    );
    _roles.removeWhere((role) => role.id == id && !role.isSystem);
    _recordSyncChange(
      entityType: 'role',
      entityId: id,
      operation: 'delete',
      payload: removed.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

  bool _isStoreOwnerUser(AppUser user) {
    return user.isSystem && user.roleId == 'admin';
  }

  Future<void> _syncStoreOwnerUserToCloud(
    AppUser current,
    AppUser desired, {
    String? password,
  }) async {
    var cache = AccountAuthCache.load();
    var token = cache?.accountToken.trim() ?? '';
    if (token.isEmpty) {
      throw const AppStoreActionException(
        'Cloud owner re-authentication required before editing the protected Store Owner.',
      );
    }

    final authService = AccountAuthService();
    final session = await authService.refreshSession(accountToken: token);
    if (session.ok) {
      cache = AccountAuthCache.load() ?? cache;
      final previous = cache;
      if (previous != null) {
        await AccountAuthCache.save(
          previous.copyWith(
            accountId: session.accountId.isNotEmpty
                ? session.accountId
                : previous.accountId,
            storeId:
                session.storeId.isNotEmpty ? session.storeId : previous.storeId,
            branchId: session.branchId.isNotEmpty
                ? session.branchId
                : previous.branchId,
            subscriptionStatus: session.subscriptionStatus.isNotEmpty
                ? session.subscriptionStatus
                : previous.subscriptionStatus,
            username: session.username.isNotEmpty
                ? session.username
                : previous.username,
            storeSlug: session.storeSlug.isNotEmpty
                ? session.storeSlug
                : previous.storeSlug,
            storeName: session.storeName.isNotEmpty
                ? session.storeName
                : previous.storeName,
            loginName: session.loginName.isNotEmpty
                ? session.loginName
                : previous.loginName,
            accountType: session.accountType.isNotEmpty
                ? session.accountType
                : previous.accountType,
            trialEndsAt: session.trialEndsAt ?? previous.trialEndsAt,
            devicesLimit: session.devicesLimit ?? previous.devicesLimit,
            adminToken: session.adminToken.isNotEmpty
                ? session.adminToken
                : previous.adminToken,
            accountToken: session.accountToken.isNotEmpty
                ? session.accountToken
                : previous.accountToken,
            cloudSyncEnabled: session.cloudSyncEnabled,
            lastVerifiedAt: DateTime.now(),
          ),
        );
      }
      token = session.accountToken.isNotEmpty ? session.accountToken : token;
    } else if (session.message.toLowerCase().contains('session') ||
        session.message.toLowerCase().contains('unauthorized') ||
        session.message.toLowerCase().contains('token') ||
        session.message.contains('401')) {
      throw const AppStoreActionException(
        'Cloud owner re-authentication required before editing the protected Store Owner.',
      );
    }

    final normalizedUsername = desired.username.trim().toLowerCase();
    final cleanName = desired.fullName.trim().isEmpty
        ? 'Administrator'
        : desired.fullName.trim();
    final result = await authService.updateOwnerProfile(
      accountToken: token,
      username: normalizedUsername,
      fullName: cleanName,
      newPassword: password,
    );
    if (!result.ok) {
      final msg = result.message.toLowerCase();
      if (msg.contains('session') ||
          msg.contains('unauthorized') ||
          msg.contains('token') ||
          msg.contains('401')) {
        throw const AppStoreActionException(
          'Cloud owner re-authentication required before editing the protected Store Owner.',
        );
      }
      throw AppStoreActionException(
        result.message.isEmpty
            ? 'Cloud rejected the Store Owner update. Local changes were not saved.'
            : result.message,
      );
    }
    cache = AccountAuthCache.load();
    if (cache != null) {
      await AccountAuthCache.save(
        cache.copyWith(
          accountId:
              result.accountId.isNotEmpty ? result.accountId : cache.accountId,
          storeId: result.storeId.isNotEmpty ? result.storeId : cache.storeId,
          branchId:
              result.branchId.isNotEmpty ? result.branchId : cache.branchId,
          subscriptionStatus: result.subscriptionStatus.isNotEmpty
              ? result.subscriptionStatus
              : cache.subscriptionStatus,
          username:
              result.username.isNotEmpty ? result.username : normalizedUsername,
          storeSlug:
              result.storeSlug.isNotEmpty ? result.storeSlug : cache.storeSlug,
          storeName:
              result.storeName.isNotEmpty ? result.storeName : cache.storeName,
          loginName:
              result.loginName.isNotEmpty ? result.loginName : cache.loginName,
          accountType: result.accountType.isNotEmpty
              ? result.accountType
              : cache.accountType,
          trialEndsAt: result.trialEndsAt ?? cache.trialEndsAt,
          devicesLimit: result.devicesLimit ?? cache.devicesLimit,
          adminToken: result.adminToken.isNotEmpty
              ? result.adminToken
              : cache.adminToken,
          accountToken: result.accountToken.isNotEmpty
              ? result.accountToken
              : cache.accountToken,
          cloudSyncEnabled: result.cloudSyncEnabled,
          lastVerifiedAt: DateTime.now(),
        ),
      );
    }
  }

  AppUser? get storeOwnerUser {
    for (final user in _users) {
      if (_isStoreOwnerUser(user)) return user;
    }
    return null;
  }

  Future<void> applyCloudStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) async {
    final owner = storeOwnerUser;
    if (owner == null) return;
    final cleanPassword = password.trim();
    if (cleanPassword.length < 6) {
      throw ArgumentError(
          'Store Owner password must be at least 6 characters.');
    }
    final index = _users.indexWhere((item) => item.id == owner.id);
    if (index == -1) return;
    final normalizedUsername = username.trim().toLowerCase().isEmpty
        ? owner.username.trim().toLowerCase()
        : username.trim().toLowerCase();
    final cleanName = (fullName ?? owner.fullName).trim().isEmpty
        ? owner.fullName
        : (fullName ?? owner.fullName).trim();
    final updated = owner.copyWith(
      username: normalizedUsername,
      fullName: cleanName,
      passwordHash: await _hashPasswordAsync(cleanPassword),
      roleId: 'admin',
      extraPermissions: const <String>{},
      deniedPermissions: const <String>{},
      isActive: true,
      isSystem: true,
      updatedAt: DateTime.now(),
    );
    _users[index] = updated;
    if (_activeUser?.id == updated.id) _activeUser = updated;
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> addOrUpdateUser(AppUser user, {String? password}) async {
    requirePermission(AppPermission.usersManage);
    if (user.fullName.trim().isEmpty || user.username.trim().isEmpty) {
      throw ArgumentError('Name and username are required.');
    }
    if (roleById(user.roleId) == null) throw ArgumentError('Role not found.');
    final normalizedUsername = user.username.trim().toLowerCase();
    final duplicate = _users.any(
      (item) =>
          item.id != user.id &&
          item.username.trim().toLowerCase() == normalizedUsername,
    );
    if (duplicate) throw ArgumentError('Username already exists.');
    final now = DateTime.now();
    final isCreate = user.id.trim().isEmpty ||
        _users.indexWhere((item) => item.id == user.id) == -1;
    if (isCreate && (password == null || password.trim().length < 4)) {
      throw ArgumentError('Password must be at least 4 characters.');
    }
    final id = isCreate ? 'user_${now.microsecondsSinceEpoch}' : user.id;
    final index = _users.indexWhere((item) => item.id == id);
    final current = index == -1 ? null : _users[index];
    final editingStoreOwner = current != null && _isStoreOwnerUser(current);

    if (editingStoreOwner) {
      if (password != null &&
          password.trim().isNotEmpty &&
          password.trim().length < 6) {
        throw ArgumentError(
            'Store Owner password must be at least 6 characters.');
      }
      if (user.roleId != 'admin' || user.isActive != true) {
        throw const AppStoreActionException(
          'Store Owner must always keep Full Access and cannot be disabled.',
        );
      }
      if (user.extraPermissions.isNotEmpty ||
          user.deniedPermissions.isNotEmpty) {
        throw const AppStoreActionException(
          'Store Owner permissions are locked and cannot have local overrides.',
        );
      }
    }

    final saved = AppUser(
      id: id,
      fullName: user.fullName.trim(),
      username: normalizedUsername,
      passwordHash: password != null && password.trim().isNotEmpty
          ? await _hashPasswordAsync(password.trim())
          : user.passwordHash,
      roleId: editingStoreOwner ? 'admin' : user.roleId,
      extraPermissions: editingStoreOwner
          ? const <String>{}
          : user.extraPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      deniedPermissions: editingStoreOwner
          ? const <String>{}
          : user.deniedPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      isActive: editingStoreOwner ? true : user.isActive,
      isSystem: editingStoreOwner ? true : user.isSystem,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
      lastLoginAt: user.lastLoginAt,
    );

    if (editingStoreOwner) {
      await _syncStoreOwnerUserToCloud(current, saved, password: password);
    }

    if (index == -1) {
      _users.add(saved);
    } else {
      if (_users[index].isSystem && saved.roleId != 'admin') {
        throw StateError('The built-in admin user must keep the Admin role.');
      }
      if (_users[index].isSystem && !editingStoreOwner) {
        throw StateError(
            'System users cannot be edited as regular local users.');
      }
      _users[index] = saved;
      if (_activeUser?.id == saved.id) _activeUser = saved;
    }
    _recordSyncChange(
      entityType: 'user',
      entityId: saved.id,
      operation: isCreate ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> deleteUser(String id) async {
    requirePermission(AppPermission.usersManage);
    final user = _users.firstWhere((item) => item.id == id);
    final adminCount =
        _users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) {
      throw StateError(
        'Create another active admin before deleting this user.',
      );
    }
    if (user.isSystem) {
      throw StateError('The built-in admin user cannot be deleted.');
    }
    _users.removeWhere((item) => item.id == id);
    _recordSyncChange(
      entityType: 'user',
      entityId: id,
      operation: 'delete',
      payload: user.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<String> _hashPasswordAsync(String password) async {
    final salt = _generateSalt();
    return compute(_hashPasswordInBackground, <String, String>{
      'password': password,
      'salt': salt,
      'iterations': _passwordHashIterations.toString(),
    });
  }

  String _hashPasswordWithSalt(
    String password,
    String salt, {
    required int iterations,
  }) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(
      Uint8List.fromList(utf8.encode('ventio|password|$password')),
    );
    return '$_passwordHashPrefix$iterations:$salt:${base64UrlEncode(hash)}';
  }

  String _hashLegacyLocalCredentialWithSalt(String password, String salt) {
    const legacyPurpose = 'store_manager_pro|local_'
        'p'
        'in_v2';
    List<int> digest = utf8.encode('$legacyPurpose|$salt|$password');
    for (var i = 0; i < 12000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '$_legacyLocalCredentialHashPrefix$salt:${base64UrlEncode(digest)}';
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  StoreProfile _loadStoreProfile() {
    final raw = LocalDatabaseService.getString(_storeProfileKey);
    if (raw == null) return StoreProfile.defaults;
    return StoreProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  void _normalizeCustomers() {
    // Keep ID as the only source of truth.
    // Do not merge, delete, or hide customers only because they share the same name.
    // Offline devices may legitimately create separate records with identical names;
    // those records are surfaced through dataConflicts after sync instead.
    final normalized = <Customer>[];
    var hasWalkIn = false;
    final seenIds = <String>{};

    for (final customer in _customers) {
      final trimmedName = customer.name.trim();
      final normalizedName = trimmedName.toLowerCase();
      final isWalkIn = customer.id == walkInCustomerId ||
          normalizedName == walkInCustomerName.toLowerCase();

      if (isWalkIn) {
        if (!hasWalkIn) {
          normalized.add(walkInCustomer);
          hasWalkIn = true;
          seenIds.add(walkInCustomerId);
        }
        continue;
      }

      if (seenIds.contains(customer.id)) {
        continue;
      }

      normalized.add(customer.copyWith(name: trimmedName));
      seenIds.add(customer.id);
    }

    if (!hasWalkIn) {
      normalized.insert(0, walkInCustomer);
    } else {
      normalized
        ..removeWhere((c) => c.id == walkInCustomerId)
        ..insert(0, walkInCustomer);
    }

    _customers
      ..clear()
      ..addAll(normalized);
    _rebuildCustomerIndexes();
  }

  Future<void> _persistProductDerivedData() async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    await Future.wait(<Future<void>>[
      LocalDatabaseService.setString(
        _priceListsKey,
        jsonEncode(_priceLists.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productPricesKey,
        jsonEncode(_productPrices.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productPriceOverridesKey,
        jsonEncode(
            _productPriceOverrides.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productCostsKey,
        jsonEncode(_productCosts.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _inventoryCostingMethodKey,
        _inventoryCostingMethod.code,
      ),
      LocalDatabaseService.setString(
        _costingMethodHistoryKey,
        jsonEncode(_costingMethodHistory.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _inventoryCostLayersKey,
        jsonEncode(_inventoryCostLayers.map((item) => item.toJson()).toList()),
      ),
    ]);
  }

  void _markProductDerivedDataDirty() {
    _productDerivedDataDirty = true;
    _productDerivedDataFlushTimer?.cancel();
    _productDerivedDataFlushTimer = Timer(
      const Duration(milliseconds: 120),
      () {
        unawaited(_flushProductDerivedData());
      },
    );
  }

  Future<void> _flushProductDerivedData() async {
    if (!_productDerivedDataDirty) return;
    final inFlight = _productDerivedDataFlushInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _persistProductDerivedData();
    _productDerivedDataFlushInFlight = future;
    _productDerivedDataDirty = false;
    try {
      await future;
    } finally {
      _productDerivedDataFlushInFlight = null;
      if (_productDerivedDataDirty) {
        _markProductDerivedDataDirty();
      }
    }
  }

  void _scheduleSaleAccounting(Sale sale) {
    if (!AccountingService.isAvailable) return;
    final saleId = sale.id.trim();
    if (saleId.isEmpty) return;
    final future = _postSaleAccounting(sale);
    _pendingSaleAccountingTasks[saleId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingSaleAccountingTasks[saleId], future)) {
          _pendingSaleAccountingTasks.remove(saleId);
        }
      }),
    );
  }

  Future<void> _postSaleAccounting(Sale sale) async {
    try {
      await AccountingService.recordSale(sale);
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.error(
          area: 'sales',
          action: 'record_sale_accounting',
          message: 'Sale accounting posting failed.',
          details: 'saleId=${sale.id} invoiceNo=${sale.invoiceNo} error=$error',
          stackTrace: stackTrace.toString(),
          userId: _activeUser?.id ?? '',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
    }
  }

  Future<void> _waitForPendingSaleAccounting(String saleId) async {
    final pending = _pendingSaleAccountingTasks[saleId.trim()];
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The background poster already logged the failure.
    }
  }

  void _schedulePurchaseAccounting(Purchase purchase) {
    if (!AccountingService.isAvailable) return;
    final purchaseId = purchase.id.trim();
    if (purchaseId.isEmpty) return;
    final future = _postPurchaseAccounting(purchase);
    _pendingPurchaseAccountingTasks[purchaseId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingPurchaseAccountingTasks[purchaseId], future)) {
          _pendingPurchaseAccountingTasks.remove(purchaseId);
        }
      }),
    );
  }

  Future<void> _postPurchaseAccounting(Purchase purchase) async {
    try {
      await AccountingService.recordPurchase(purchase);
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.error(
          area: 'purchases',
          action: 'record_purchase_accounting',
          message: 'Purchase accounting posting failed.',
          details:
              'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} error=$error',
          stackTrace: stackTrace.toString(),
          userId: _activeUser?.id ?? '',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
    }
  }

  Future<void> _waitForPendingPurchaseAccounting(String purchaseId) async {
    final pending = _pendingPurchaseAccountingTasks[purchaseId.trim()];
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The background poster already logged the failure.
    }
  }

  void _scheduleExpenseAccounting(Expense expense) {
    if (!AccountingService.isAvailable) return;
    final expenseId = expense.id.trim();
    if (expenseId.isEmpty) return;
    final future = _postExpenseAccounting(expense);
    _pendingExpenseAccountingTasks[expenseId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingExpenseAccountingTasks[expenseId], future)) {
          _pendingExpenseAccountingTasks.remove(expenseId);
        }
      }),
    );
  }

  Future<void> _postExpenseAccounting(Expense expense) async {
    try {
      await AccountingService.recordExpense(expense);
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.error(
          area: 'expenses',
          action: 'record_expense_accounting',
          message: 'Expense accounting posting failed.',
          details:
              'expenseId=${expense.id} title=${expense.title} error=$error',
          stackTrace: stackTrace.toString(),
          userId: _activeUser?.id ?? '',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
    }
  }

  Future<void> _waitForPendingExpenseAccounting(String expenseId) async {
    final pending = _pendingExpenseAccountingTasks[expenseId.trim()];
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The background poster already logged the failure.
    }
  }

  void _rebuildProductIndexes() {
    _productIndexById.clear();
    _productIdByNormalizedCode.clear();
    _productIdByNormalizedBarcode.clear();
    for (var i = 0; i < _products.length; i += 1) {
      final product = _products[i];
      _productIndexById[product.id] = i;
      if (product.isDeleted) continue;
      final code = product.code.trim().toLowerCase();
      if (code.isNotEmpty) _productIdByNormalizedCode[code] = product.id;
      final barcode = product.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        _productIdByNormalizedBarcode[barcode] = product.id;
      }
    }
    _cachedProducts = null;
    _cachedProductsGeneration = -1;
  }

  void _ensureProductsCache() {
    if (_cachedProductsGeneration == _productsRevision &&
        _cachedProducts != null) {
      return;
    }
    _cachedProducts = List.unmodifiable(
      _sortedProducts(
        _products.where((item) => !item.isDeleted).toList(growable: false),
      ),
    );
    _cachedProductsGeneration = _productsRevision;
  }

  void _ensureStockTrackedProductsCache() {
    if (_cachedStockTrackedProductsGeneration == _productsRevision &&
        _cachedStockTrackedProducts != null) {
      return;
    }
    _ensureProductsCache();
    _cachedStockTrackedProducts = List.unmodifiable(
      _cachedProducts!.where((item) => item.trackStock).toList(growable: false),
    );
    _cachedStockTrackedProductsGeneration = _productsRevision;
  }

  void _rebuildCustomerIndexes() {
    _customerIndexById.clear();
    _customerIdByNormalizedName.clear();
    for (var i = 0; i < _customers.length; i += 1) {
      final customer = _customers[i];
      _customerIndexById[customer.id] = i;
      if (customer.isDeleted) continue;
      final normalizedName = customer.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _customerIdByNormalizedName[normalizedName] = customer.id;
      }
    }
  }

  void _rebuildSupplierIndexes() {
    _supplierIndexById.clear();
    _supplierIdByNormalizedName.clear();
    for (var i = 0; i < _suppliers.length; i += 1) {
      final supplier = _suppliers[i];
      _supplierIndexById[supplier.id] = i;
      if (supplier.isDeleted) continue;
      final normalizedName = supplier.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _supplierIdByNormalizedName[normalizedName] = supplier.id;
      }
    }
  }

  void _rebuildMutableEntityIndexes() {
    _rebuildProductIndexes();
    _rebuildCustomerIndexes();
    _rebuildSupplierIndexes();
    _rebuildPurchaseIndexes();
    _rebuildExpenseIndexes();
    _rebuildAccountTransactionIndexes();
    _rebuildStockMovementIndexes();
  }

  void _rebuildStockMovementIndexes() {
    _stockMovementIndexById.clear();
    for (var i = 0; i < _stockMovements.length; i++) {
      final id = _stockMovements[i].id.trim();
      if (id.isEmpty) continue;
      _stockMovementIndexById[id] = i;
    }
  }

  int _stockMovementIndexForId(String id) =>
      _stockMovementIndexById[id.trim()] ?? -1;

  void _rebuildPurchaseIndexes() {
    _purchaseIndexById.clear();
    for (var i = 0; i < _purchases.length; i++) {
      final id = _purchases[i].id.trim();
      if (id.isEmpty) continue;
      _purchaseIndexById[id] = i;
    }
  }

  int _purchaseIndexForId(String id) => _purchaseIndexById[id.trim()] ?? -1;

  Future<Sale?> _saleByIdFromSqlite(String id) {
    return LocalDatabaseService.getSaleFromSqliteById(id);
  }

  Future<Purchase?> _purchaseByIdFromSqlite(String id) {
    return LocalDatabaseService.getPurchaseFromSqliteById(id);
  }

  void _putStockMovementAtIndex(StockMovement movement, int index) {
    final id = movement.id.trim();
    if (id.isEmpty) return;
    if (index == _stockMovements.length) {
      _stockMovements.add(movement);
    } else {
      _stockMovements[index] = movement;
    }
    _stockMovementIndexById[id] = index;
    _warehouseStockCacheDirty = true;
  }

  void _rebuildExpenseIndexes() {
    _expenseIndexById.clear();
    for (var i = 0; i < _expenses.length; i++) {
      final id = _expenses[i].id.trim();
      if (id.isEmpty) continue;
      _expenseIndexById[id] = i;
    }
  }

  void _rebuildAccountTransactionIndexes() {
    _accountTransactionIndexById.clear();
    for (var i = 0; i < _accountTransactions.length; i++) {
      final id = _accountTransactions[i].id.trim();
      if (id.isEmpty) continue;
      _accountTransactionIndexById[id] = i;
    }
  }

  int _expenseIndexForId(String id) => _expenseIndexById[id.trim()] ?? -1;

  int _accountTransactionIndexForId(String id) =>
      _accountTransactionIndexById[id.trim()] ?? -1;

  void _touchDataRevisions({
    bool products = false,
    bool customers = false,
    bool sales = false,
    bool deliveryNotes = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
  }) {
    if (products) {
      _productsRevision += 1;
      _warehouseStockCacheDirty = true;
      _cachedProducts = null;
      _cachedProductsGeneration = -1;
      _cachedStockTrackedProducts = null;
      _cachedStockTrackedProductsGeneration = -1;
    }
    if (customers) _customersRevision += 1;
    if (sales) {
      _salesRevision += 1;
      _cachedSales = null;
      _cachedSalesGeneration = -1;
    }
    if (deliveryNotes) {
      _deliveryNotesRevision += 1;
      _cachedDeliveryNotes = null;
      _cachedDeliveryNotesGeneration = -1;
      _cachedDeliveryNoteBySaleId = null;
      _cachedDeliveryNoteBySaleIdGeneration = -1;
    }
    if (suppliers) _suppliersRevision += 1;
    if (supplierProductPrices) _supplierProductPricesRevision += 1;
    if (expenses) {
      _expensesRevision += 1;
      _cachedExpensesOverview = null;
      _cachedExpensesOverviewRevision = -1;
    }
    if (purchases) {
      _purchasesRevision += 1;
      _purchaseInsightsCacheDirty = true;
      _cachedPurchasesOverview = null;
      _cachedPurchasesOverviewRevision = -1;
      _cachedPurchasesOverviewMonthKey = '';
    }
    if (stockMovements) {
      _stockMovementsRevision += 1;
      _warehouseStockCacheDirty = true;
    }
    if (inventoryCounts) _inventoryCountsRevision += 1;
    if (warehouses) {
      _warehousesRevision += 1;
      _warehouseStockCacheDirty = true;
    }
    if (accountTransactions) {
      _accountTransactionsRevision += 1;
      _accountLedgerCacheDirty = true;
    }
    if (storeProfile) _storeProfileRevision += 1;
  }

  void _touchPurchasesData() {
    _touchDataRevisions(purchases: true);
  }

  void _touchExpensesData() {
    _touchDataRevisions(expenses: true);
  }

  void _putPurchaseAtIndex(Purchase purchase, int index) {
    final id = purchase.id.trim();
    if (id.isEmpty) return;
    if (index == _purchases.length) {
      _purchases.add(purchase);
    } else {
      _purchases[index] = purchase;
    }
    _purchaseIndexById[id] = index;
  }

  void _removePurchaseAtIndex(int index) {
    if (index < 0 || index >= _purchases.length) return;
    final removedId = _purchases[index].id.trim();
    _purchases.removeAt(index);
    if (removedId.isNotEmpty) {
      _purchaseIndexById.remove(removedId);
    }
    for (var i = index; i < _purchases.length; i++) {
      final id = _purchases[i].id.trim();
      if (id.isNotEmpty) {
        _purchaseIndexById[id] = i;
      }
    }
  }

  void _putExpenseAtIndex(Expense expense, int index) {
    final id = expense.id.trim();
    if (id.isEmpty) return;
    if (index == _expenses.length) {
      _expenses.add(expense);
    } else {
      _expenses[index] = expense;
    }
    _expenseIndexById[id] = index;
  }

  void _putAccountTransactionAtIndex(
      AccountTransaction transaction, int index) {
    final id = transaction.id.trim();
    if (id.isEmpty) return;
    if (index == _accountTransactions.length) {
      _accountTransactions.add(transaction);
    } else {
      _accountTransactions[index] = transaction;
    }
    _accountTransactionIndexById[id] = index;
  }

  void _removeExpenseAtIndex(int index) {
    if (index < 0 || index >= _expenses.length) return;
    final removedId = _expenses[index].id.trim();
    _expenses.removeAt(index);
    if (removedId.isNotEmpty) {
      _expenseIndexById.remove(removedId);
    }
    for (var i = index; i < _expenses.length; i++) {
      final id = _expenses[i].id.trim();
      if (id.isNotEmpty) {
        _expenseIndexById[id] = i;
      }
    }
  }

  void _removeAccountTransactionAtIndex(int index) {
    if (index < 0 || index >= _accountTransactions.length) return;
    final removedId = _accountTransactions[index].id.trim();
    _accountTransactions.removeAt(index);
    if (removedId.isNotEmpty) {
      _accountTransactionIndexById.remove(removedId);
    }
    for (var i = index; i < _accountTransactions.length; i++) {
      final id = _accountTransactions[i].id.trim();
      if (id.isNotEmpty) {
        _accountTransactionIndexById[id] = i;
      }
    }
  }

  String resolveCustomerName(String? customerId) {
    if (customerId == null ||
        customerId.isEmpty ||
        customerId == walkInCustomerId) {
      return walkInCustomerName;
    }
    final index = _customerIndexById[customerId];
    if (index == null ||
        index < 0 ||
        index >= _customers.length ||
        _customers[index].isDeleted) {
      return walkInCustomerName;
    }
    return _customers[index].name;
  }

  String sanitizeSelectedCustomerId(String? customerId) {
    final normalized = customerId?.trim();
    if (normalized == null || normalized.isEmpty) return walkInCustomerId;
    final index = _customerIndexById[normalized];
    if (index == null || index < 0 || index >= _customers.length) {
      return walkInCustomerId;
    }
    return _customers[index].isDeleted ? walkInCustomerId : normalized;
  }

  static const int _syncMaintenanceKeepRecentChanges = 200;
  static const int _syncMaintenanceMinChangesBeforeCompact = 1000;

  /// Automatic event-log compaction is intentionally not run from normal save
  /// calls. It is async, Host-only, and must be guarded by ACK-based safety
  /// checks, so sync transports call [compactSyncedSyncHistoryForMaintenance]
  /// after a successful sync/ACK cycle.
  void _compactSyncedHistory() {
    return;
  }

  int _earliestStoredAuthoritativeSequence() {
    var earliest = 0;
    for (final change in _syncChanges) {
      if (change.sequence <= 0) continue;
      if (earliest == 0 || change.sequence < earliest) {
        earliest = change.sequence;
      }
    }
    return earliest;
  }

  int _latestStoredAuthoritativeSequence() {
    var latest = _syncSequence;
    for (final change in _syncChanges) {
      if (change.sequence > latest) latest = change.sequence;
    }
    return latest;
  }

  int _minimumActivePeerAckSequence({
    Duration activeWindow = const Duration(days: 14),
  }) {
    if (!appIdentity.isHost) return _latestStoredAuthoritativeSequence();
    final now = DateTime.now();
    final activePeers = SyncDeviceStateStore.loadPeerStates().where((peer) {
      final seen = peer.lastSeenAt ?? peer.updatedAt;
      if (seen == null) return false;
      return now.difference(seen) <= activeWindow;
    }).toList();
    if (activePeers.isEmpty) return 0;
    return activePeers.fold<int>(1 << 62, (minSeq, peer) {
      final seq = peer.lastAckSequence > 0
          ? peer.lastAckSequence
          : peer.lastAppliedSequence;
      if (seq <= 0) return 0;
      return seq < minSeq ? seq : minSeq;
    });
  }

  Future<void> _saveSyncStateOnly() async {
    // Hot-path performance fix: sync status/queue updates must not persist the
    // entire business dataset. Rewriting products, sales, purchases, and stock
    // movements on every sync acknowledgement makes normal data entry slower
    // as the database grows. Persist only the sync tables and sequence here.
    //
    // Use the normal key writer instead of only the SQLite dirty lists because
    // many sync paths mutate existing rows (mark synced/rejected/clear queue).
    // The SQLite backend already merges these rows instead of full deleting,
    // while legacy JSON storage/legacy storage still receives the compact sync-only JSON.
    await Future.wait([
      LocalDatabaseService.setString(
        _syncChangesKey,
        jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _syncQueueKey,
        jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _syncSequenceKey,
        _syncSequence.toString(),
      ),
    ]);
  }

  Future<void> _saveAll() async {
    _normalizeCustomers();
    _replaceUsersWithoutDuplicates(List<AppUser>.from(_users));
    _compactSyncedHistory();
    await Future.wait([
      LocalDatabaseService.setString(
        _productsKey,
        jsonEncode(_products.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _customersKey,
        jsonEncode(_customers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _salesKey,
        jsonEncode(_sales.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _saleQuotationsKey,
        jsonEncode(_saleQuotations.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _deliveryNotesKey,
        jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _billsOfMaterialsKey,
        jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _manufacturingOrdersKey,
        jsonEncode(_manufacturingOrders.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _suppliersKey,
        jsonEncode(_suppliers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _supplierProductPricesKey,
        jsonEncode(
          _supplierProductPrices.map((item) => item.toJson()).toList(),
        ),
      ),
      LocalDatabaseService.setString(
        _priceListsKey,
        jsonEncode(_priceLists.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productPricesKey,
        jsonEncode(_productPrices.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productPriceOverridesKey,
        jsonEncode(
            _productPriceOverrides.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _productCostsKey,
        jsonEncode(_productCosts.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _costingMethodHistoryKey,
        jsonEncode(_costingMethodHistory.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _inventoryCostLayersKey,
        jsonEncode(_inventoryCostLayers.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
          _inventoryCostingMethodKey, _inventoryCostingMethod.code),
      LocalDatabaseService.setString(
        _categoriesKey,
        jsonEncode(_categories.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _brandsKey,
        jsonEncode(_brands.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _unitsKey,
        jsonEncode(_units.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _expensesKey,
        jsonEncode(_expenses.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _purchasesKey,
        jsonEncode(_purchases.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _stockMovementsKey,
        jsonEncode(_stockMovements.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _inventoryCountsKey,
        jsonEncode(_inventoryCounts.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _warehousesKey,
        jsonEncode(_warehouses.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _accountTransactionsKey,
        jsonEncode(_accountTransactions.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _syncChangesKey,
        jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(
        _syncQueueKey,
        jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
      ),
      LocalDatabaseService.setString(_deviceIdKey, _deviceId),
      LocalDatabaseService.setString(
        _storeProfileKey,
        jsonEncode(_storeProfile.toJson()),
      ),
      LocalDatabaseService.setString(
        _invoiceCounterKey,
        _invoiceCounter.toString(),
      ),
      LocalDatabaseService.setString(
        _purchaseCounterKey,
        _purchaseCounter.toString(),
      ),
      LocalDatabaseService.setString(
        _syncSequenceKey,
        _syncSequence.toString(),
      ),
      LocalDatabaseService.setString(_schemaVersionKey, '17'),
    ]);
  }

  Future<void> _saveDirty({
    bool products = false,
    bool productDerivedData = true,
    bool customers = false,
    bool sales = false,
    bool saleQuotations = false,
    bool deliveryNotes = false,
    bool billsOfMaterials = false,
    bool manufacturingOrders = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool categories = false,
    bool brands = false,
    bool units = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    _touchDataRevisions(
      products: products,
      customers: customers,
      sales: sales,
      suppliers: suppliers,
      supplierProductPrices: supplierProductPrices,
      expenses: expenses,
      purchases: purchases,
      stockMovements: stockMovements,
      inventoryCounts: inventoryCounts,
      warehouses: warehouses,
      accountTransactions: accountTransactions,
      storeProfile: storeProfile,
    );
    if (LocalDatabaseService.isSqliteAuthoritative) {
      await _traceAsync(
        'saveDirty',
        'sqlite_hot_path',
        () => _saveDirtySqliteHotPath(
          products: products,
          productDerivedData: productDerivedData,
          customers: customers,
          sales: sales,
          saleQuotations: saleQuotations,
          deliveryNotes: deliveryNotes,
          billsOfMaterials: billsOfMaterials,
          manufacturingOrders: manufacturingOrders,
          suppliers: suppliers,
          supplierProductPrices: supplierProductPrices,
          categories: categories,
          brands: brands,
          units: units,
          expenses: expenses,
          purchases: purchases,
          stockMovements: stockMovements,
          inventoryCounts: inventoryCounts,
          warehouses: warehouses,
          accountTransactions: accountTransactions,
          storeProfile: storeProfile,
          invoiceCounter: invoiceCounter,
          purchaseCounter: purchaseCounter,
          sync: sync,
        ),
        metadata: <String, Object?>{
          'products': products,
          'productDerivedData': productDerivedData,
          'customers': customers,
          'sales': sales,
          'suppliers': suppliers,
          'purchases': purchases,
          'stockMovements': stockMovements,
          'accountTransactions': accountTransactions,
          'sync': sync,
        },
      );
      return;
    }

    final writes = <Future<void>>[];
    if (sync) {
      _traceSync('saveDirty', 'compact_sync_history', _compactSyncedHistory);
    }
    if (products) {
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_products',
          () => LocalDatabaseService.setString(
            _productsKey,
            jsonEncode(_products.map((item) => item.toJson()).toList()),
          ),
        ),
      );
    }
    if (productDerivedData) {
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_costs',
          () => LocalDatabaseService.setString(
            _productCostsKey,
            jsonEncode(_productCosts.map((item) => item.toJson()).toList()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_price_lists',
          () => LocalDatabaseService.setString(
            _priceListsKey,
            jsonEncode(_priceLists.map((item) => item.toJson()).toList()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_prices',
          () => LocalDatabaseService.setString(
            _productPricesKey,
            jsonEncode(_productPrices.map((item) => item.toJson()).toList()),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_product_price_overrides',
          () => LocalDatabaseService.setString(
            _productPriceOverridesKey,
            jsonEncode(
              _productPriceOverrides.map((item) => item.toJson()).toList(),
            ),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_inventory_costing_method',
          () => LocalDatabaseService.setString(
            _inventoryCostingMethodKey,
            _inventoryCostingMethod.code,
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_costing_history',
          () => LocalDatabaseService.setString(
            _costingMethodHistoryKey,
            jsonEncode(
              _costingMethodHistory.map((item) => item.toJson()).toList(),
            ),
          ),
        ),
      );
      writes.add(
        _traceAsync(
          'saveDirty',
          'write_inventory_layers',
          () => LocalDatabaseService.setString(
            _inventoryCostLayersKey,
            jsonEncode(
                _inventoryCostLayers.map((item) => item.toJson()).toList()),
          ),
        ),
      );
    }
    if (customers) {
      writes.add(_traceAsync(
          'saveDirty',
          'write_customers',
          () => LocalDatabaseService.setString(_customersKey,
              jsonEncode(_customers.map((item) => item.toJson()).toList()))));
    }
    if (sales) {
      writes.add(_traceAsync(
          'saveDirty',
          'write_sales',
          () => LocalDatabaseService.setString(_salesKey,
              jsonEncode(_sales.map((item) => item.toJson()).toList()))));
    }
    if (saleQuotations) {
      writes.add(
        LocalDatabaseService.setString(
          _saleQuotationsKey,
          jsonEncode(_saleQuotations.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (deliveryNotes) {
      writes.add(
        LocalDatabaseService.setString(
          _deliveryNotesKey,
          jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (billsOfMaterials) {
      writes.add(
        LocalDatabaseService.setString(
          _billsOfMaterialsKey,
          jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (manufacturingOrders) {
      writes.add(
        LocalDatabaseService.setString(
          _manufacturingOrdersKey,
          jsonEncode(
            _manufacturingOrders.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (suppliers) {
      writes.add(
        LocalDatabaseService.setString(
          _suppliersKey,
          jsonEncode(_suppliers.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (supplierProductPrices) {
      writes.add(
        LocalDatabaseService.setString(
          _supplierProductPricesKey,
          jsonEncode(
            _supplierProductPrices.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (categories) {
      writes.add(
        LocalDatabaseService.setString(
          _categoriesKey,
          jsonEncode(_categories.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (brands) {
      writes.add(
        LocalDatabaseService.setString(
          _brandsKey,
          jsonEncode(_brands.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (units) {
      writes.add(
        LocalDatabaseService.setString(
          _unitsKey,
          jsonEncode(_units.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (expenses) {
      writes.add(
        LocalDatabaseService.setString(
          _expensesKey,
          jsonEncode(_expenses.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (purchases) {
      writes.add(
        LocalDatabaseService.setString(
          _purchasesKey,
          jsonEncode(_purchases.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (stockMovements) {
      writes.add(
        LocalDatabaseService.setString(
          _stockMovementsKey,
          jsonEncode(_stockMovements.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (inventoryCounts) {
      writes.add(
        LocalDatabaseService.setString(
          _inventoryCountsKey,
          jsonEncode(_inventoryCounts.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (warehouses) {
      writes.add(
        LocalDatabaseService.setString(
          _warehousesKey,
          jsonEncode(_warehouses.map((item) => item.toJson()).toList()),
        ),
      );
    }
    if (accountTransactions) {
      writes.add(
        LocalDatabaseService.setString(
          _accountTransactionsKey,
          jsonEncode(
            _accountTransactions.map((item) => item.toJson()).toList(),
          ),
        ),
      );
    }
    if (storeProfile) {
      writes.add(
        LocalDatabaseService.setString(
          _storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        ),
      );
    }
    if (invoiceCounter) {
      writes.add(
        LocalDatabaseService.setString(
          _invoiceCounterKey,
          _invoiceCounter.toString(),
        ),
      );
    }
    if (purchaseCounter) {
      writes.add(
        LocalDatabaseService.setString(
          _purchaseCounterKey,
          _purchaseCounter.toString(),
        ),
      );
    }
    if (sync) {
      writes
        ..add(
          LocalDatabaseService.setString(
            _syncChangesKey,
            jsonEncode(_syncChanges.map((item) => item.toJson()).toList()),
          ),
        )
        ..add(
          LocalDatabaseService.setString(
            _syncQueueKey,
            jsonEncode(_syncQueue.map((item) => item.toJson()).toList()),
          ),
        )
        ..add(
          LocalDatabaseService.setString(
            _syncSequenceKey,
            _syncSequence.toString(),
          ),
        );
    }
    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

  Future<void> _saveDirtySqliteHotPath({
    bool products = false,
    bool productDerivedData = true,
    bool customers = false,
    bool sales = false,
    bool saleQuotations = false,
    bool deliveryNotes = false,
    bool billsOfMaterials = false,
    bool manufacturingOrders = false,
    bool suppliers = false,
    bool supplierProductPrices = false,
    bool categories = false,
    bool brands = false,
    bool units = false,
    bool expenses = false,
    bool purchases = false,
    bool stockMovements = false,
    bool inventoryCounts = false,
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    final writes = <Future<void>>[];

    Future<void> persistRows(String key) async {
      final rows = _sqliteDirtyBusinessRows.remove(key);
      if (rows == null || rows.isEmpty) return;
      for (final payload in rows.values) {
        await LocalDatabaseService.upsertBusinessEntityJson(key, payload);
      }
    }

    if (products) {
      writes.add(persistRows(_productsKey));
    }
    if (productDerivedData) _markProductDerivedDataDirty();
    if (customers) writes.add(persistRows(_customersKey));
    if (sales) writes.add(persistRows(_salesKey));
    if (saleQuotations) {
      writes.add(persistRows(_saleQuotationsKey));
    }
    if (deliveryNotes) {
      writes.add(persistRows(_deliveryNotesKey));
    }
    if (billsOfMaterials) {
      writes.add(persistRows(_billsOfMaterialsKey));
    }
    if (manufacturingOrders) {
      writes.add(persistRows(_manufacturingOrdersKey));
    }
    if (suppliers) writes.add(persistRows(_suppliersKey));
    if (supplierProductPrices) {
      writes.add(persistRows(_supplierProductPricesKey));
    }
    if (categories) writes.add(persistRows(_categoriesKey));
    if (brands) writes.add(persistRows(_brandsKey));
    if (units) writes.add(persistRows(_unitsKey));
    if (expenses) writes.add(persistRows(_expensesKey));
    if (purchases) writes.add(persistRows(_purchasesKey));
    if (stockMovements) writes.add(persistRows(_stockMovementsKey));
    if (inventoryCounts) {
      writes.add(persistRows(_inventoryCountsKey));
    }
    if (warehouses) {
      writes.add(persistRows(_warehousesKey));
    }
    if (accountTransactions) writes.add(persistRows(_accountTransactionsKey));

    if (storeProfile) {
      writes.add(
        LocalDatabaseService.setString(
          _storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        ),
      );
    }
    if (invoiceCounter) {
      writes.add(
        LocalDatabaseService.setString(
          _invoiceCounterKey,
          _invoiceCounter.toString(),
        ),
      );
    }
    if (purchaseCounter) {
      writes.add(
        LocalDatabaseService.setString(
          _purchaseCounterKey,
          _purchaseCounter.toString(),
        ),
      );
    }

    if (sync) {
      final dirtyChanges = List<SyncChange>.from(_sqliteDirtySyncChanges);
      final dirtyQueue = List<SyncQueueItem>.from(_sqliteDirtySyncQueue);
      _sqliteDirtySyncChanges.clear();
      _sqliteDirtySyncQueue.clear();
      for (final change in dirtyChanges) {
        writes.add(LocalDatabaseService.upsertSyncChange(change));
      }
      for (final item in dirtyQueue) {
        writes.add(LocalDatabaseService.upsertSyncQueueItem(item));
      }
      writes.add(
        LocalDatabaseService.setString(
          _syncSequenceKey,
          _syncSequence.toString(),
        ),
      );
    }

    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

  Product? _findProductById(String id) {
    final index = _productIndexById[id];
    if (index == null) return null;
    if (index < 0 || index >= _products.length) return null;
    final product = _products[index];
    return product.id == id ? product : null;
  }

  // Default import-section selector for internal full-replace/reset paths.
  // The manual Backup Import flow defines a local `wants` function that
  // shadows this method and uses the user-selected section IDs.
  bool wants(String id) => true;

  Product? findProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    final productId = _productIdByNormalizedCode[normalized] ??
        _productIdByNormalizedBarcode[normalized];
    if (productId != null) return _findProductById(productId);
    final matches = _products
        .where((product) => !product.isDeleted)
        .where(
          (product) => product.effectiveSaleUnits.any(
            (unit) =>
                unit.barcode.trim().isNotEmpty &&
                unit.barcode.trim().toLowerCase() == normalized,
          ),
        )
        .toList();
    if (matches.length != 1) return null;
    return matches.first;
  }

  void _resetBusinessDataInMemory({bool keepStoreProfile = true}) {
    _products.clear();
    _customers
      ..clear()
      ..add(walkInCustomer);
    _productPrices.clear();
    _productPriceOverrides.clear();
    _productCosts.clear();
    _inventoryCostLayers.clear();
    _productPriceByLookupKey.clear();
    _productCostByProductId.clear();
    _productCostIndexByProductId.clear();
    _inventoryCostLayerIndexById.clear();
    _sales.clear();
    _suppliers.clear();
    _supplierProductPrices.clear();
    _expenses.clear();
    _purchases.clear();
    _stockMovements.clear();
    _accountTransactions.clear();
    _purchaseIndexById.clear();
    _stockMovementIndexById.clear();
    _expenseIndexById.clear();
    _accountTransactionIndexById.clear();
    _accountLedgerCacheDirty = true;
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      inventoryCounts: true,
      warehouses: true,
      accountTransactions: true,
      storeProfile: !keepStoreProfile,
    );
    _invalidateDerivedDataCaches();
    if (!keepStoreProfile) {
      _storeProfile = StoreProfile.defaults;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
  }

  Future<void> resetBusinessData({bool keepStoreProfile = true}) async {
    requirePermission(AppPermission.backupRestore);

    // Local-only reset. This must never create a SyncChange or propagate delete
    // operations to Clients. Host factory reset is handled by factoryResetLocalDevice().
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> clearLocalDeviceBusinessData({
    bool keepStoreProfile = true,
  }) async {
    // Client-only maintenance operation. This must never create a SyncChange or
    // deletion event because the Host remains the source of truth. It also
    // clears pull cursors so the next sync can rebuild from a full Host
    // snapshot instead of resuming after stale local leftovers.
    final identity = appIdentity;
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    }
    final lanRaw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (lanRaw != null && lanRaw.trim().isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(lanRaw) as Map);
        decoded.remove('lastPullCursor');
        decoded['lastSyncAt'] = null;
        await LocalDatabaseService.setString(
          'lan_sync_settings_v2',
          jsonEncode(decoded),
        );
      } catch (_) {
        // Keep the data clear even if old LAN settings are malformed.
      }
    }
    _appIdentity = identity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    );
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    await _saveAll();
    notifyListeners();
  }

  Future<int> clearLocalOnlyPendingSyncChanges() async {
    requirePermission(AppPermission.settingsManage);
    final invalidChangeIds = _syncChanges
        .where(
          (change) =>
              !change.isSynced &&
              change.entityType == 'app_identity' &&
              change.operation == 'update',
        )
        .map((change) => change.id)
        .toSet();
    if (invalidChangeIds.isEmpty) return 0;

    final beforeQueue = _syncQueue.length;
    _syncQueue.removeWhere(
      (item) => invalidChangeIds.contains(item.changeId) && !item.isSynced,
    );
    final removedQueueRows = beforeQueue - _syncQueue.length;

    final queuedInvalidIds = _syncQueue.map((item) => item.changeId).toSet();
    _syncChanges.removeWhere(
      (change) =>
          invalidChangeIds.contains(change.id) &&
          !queuedInvalidIds.contains(change.id),
    );

    await _saveSyncStateOnly();
    notifyListeners();
    return removedQueueRows;
  }

  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  }) async {
    if (enforcePermission) {
      requirePermission(AppPermission.settingsManage);
    }
    _products.clear();
    _customers
      ..clear()
      ..add(walkInCustomer);
    _sales.clear();
    _suppliers.clear();
    _supplierProductPrices.clear();
    _expenses.clear();
    _purchases.clear();
    _stockMovements.clear();
    _accountTransactions.clear();
    _purchaseIndexById.clear();
    _expenseIndexById.clear();
    _accountTransactionIndexById.clear();
    _stockMovementIndexById.clear();
    _touchPurchasesData();
    _touchExpensesData();
    _categories.clear();
    _brands.clear();
    _units.clear();
    _syncChanges.clear();
    _syncQueue.clear();
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _storeProfile = StoreProfile.defaults;
    AccountingService.configureMoneyPolicy(_storeProfile);
    _activeUser = null;
    _rememberLogin = false;
    if (!preserveAdminUsers) {
      _users.clear();
      _roles.clear();
      await _ensureDefaultAdminUser();
    }
    _deviceId = _generatePrefixedId('DV');
    _appIdentity = AppIdentity.defaults(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    ).copyWith(deviceRole: DeviceRole.standalone, syncMode: SyncMode.localOnly);
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    await LocalDatabaseService.setString(_activeUserKey, '');
    await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    }
    await LocalDatabaseService.deleteString('lan_sync_settings_v2');
    _touchDataRevisions(
      products: true,
      customers: true,
      sales: true,
      suppliers: true,
      supplierProductPrices: true,
      expenses: true,
      purchases: true,
      stockMovements: true,
      accountTransactions: true,
      storeProfile: true,
    );
    _invalidateDerivedDataCaches();
    await _saveAll();
    notifyListeners();
  }

  bool _hasPendingSyncFor(String entityType, String entityId) {
    final changesById = {for (final change in _syncChanges) change.id: change};
    final pendingChangeIds = _syncQueue
        .where((item) {
          if (item.status == 'synced') return false;
          final change = changesById[item.changeId];
          // Stale pending queue rows tied to already-synced local drafts must
          // not protect those draft changes from compaction.
          if (change != null && change.isSynced && change.sequence <= 0) {
            return false;
          }
          return true;
        })
        .map((item) => item.changeId)
        .toSet();
    return _syncChanges.any(
      (change) =>
          pendingChangeIds.contains(change.id) &&
          change.entityType == entityType &&
          change.entityId == entityId,
    );
  }

  Future<int> cleanupSoftDeletedRecords({
    Duration retention = const Duration(days: 30),
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    var removed = 0;
    var productsChanged = false;
    var catalogChanged = false;
    var customersChanged = false;
    var suppliersChanged = false;
    var supplierProductPricesChanged = false;
    var expensesChanged = false;
    var salesChanged = false;
    var purchasesChanged = false;

    bool expired(DateTime? deletedAt) =>
        deletedAt != null && deletedAt.isBefore(cutoff);

    final beforeProducts = _products.length;
    _products.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          !_hasPendingSyncFor('product', item.id) &&
          !isProductReferenced(item.id),
    );
    removed += beforeProducts - _products.length;
    productsChanged = productsChanged || beforeProducts != _products.length;

    final beforeCustomers = _customers.length;
    _customers.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          item.id != 'walk_in' &&
          !_hasPendingSyncFor('customer', item.id),
    );
    removed += beforeCustomers - _customers.length;
    customersChanged = customersChanged || beforeCustomers != _customers.length;

    final beforeSuppliers = _suppliers.length;
    _suppliers.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('supplier', item.id),
    );
    removed += beforeSuppliers - _suppliers.length;
    suppliersChanged = suppliersChanged || beforeSuppliers != _suppliers.length;

    final beforeSupplierProductPrices = _supplierProductPrices.length;
    _supplierProductPrices.removeWhere(
      (item) =>
          expired(item.deletedAt) &&
          !_hasPendingSyncFor('supplier_product_price', item.id),
    );
    removed += beforeSupplierProductPrices - _supplierProductPrices.length;
    supplierProductPricesChanged = supplierProductPricesChanged ||
        beforeSupplierProductPrices != _supplierProductPrices.length;

    final beforeExpenses = _expenses.length;
    _expenses.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('expense', item.id),
    );
    removed += beforeExpenses - _expenses.length;
    expensesChanged = expensesChanged || beforeExpenses != _expenses.length;

    final beforeCategories = _categories.length;
    _categories.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('category', item.id),
    );
    removed += beforeCategories - _categories.length;
    catalogChanged = catalogChanged || beforeCategories != _categories.length;

    final beforeBrands = _brands.length;
    _brands.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('brand', item.id),
    );
    removed += beforeBrands - _brands.length;
    catalogChanged = catalogChanged || beforeBrands != _brands.length;

    final beforeUnits = _units.length;
    _units.removeWhere(
      (item) => expired(item.deletedAt) && !_hasPendingSyncFor('unit', item.id),
    );
    removed += beforeUnits - _units.length;
    catalogChanged = catalogChanged || beforeUnits != _units.length;

    final beforeSales = _sales.length;
    _sales.removeWhere(
      (item) => expired(item.deletedAt) && !_hasPendingSyncFor('sale', item.id),
    );
    removed += beforeSales - _sales.length;
    salesChanged = salesChanged || beforeSales != _sales.length;

    final beforePurchases = _purchases.length;
    _purchases.removeWhere(
      (item) =>
          expired(item.deletedAt) && !_hasPendingSyncFor('purchase', item.id),
    );
    removed += beforePurchases - _purchases.length;
    purchasesChanged = purchasesChanged || beforePurchases != _purchases.length;

    if (removed > 0) {
      if (productsChanged) {
        _rebuildProductIndexes();
        _rebuildProductPricingLookupCaches();
      }
      if (customersChanged) {
        _rebuildCustomerIndexes();
      }
      if (suppliersChanged) {
        _rebuildSupplierIndexes();
      }
      if (supplierProductPricesChanged) {
        _markSingleSupplierPerProductAsPreferred();
      }
      if (expensesChanged) {
        _rebuildExpenseIndexes();
      }
      if (purchasesChanged) {
        _rebuildPurchaseIndexes();
      }
      _touchDataRevisions(
        products: productsChanged || catalogChanged,
        customers: customersChanged,
        sales: salesChanged,
        suppliers: suppliersChanged,
        supplierProductPrices: supplierProductPricesChanged,
        expenses: expensesChanged,
        purchases: purchasesChanged,
      );
      if (productsChanged ||
          customersChanged ||
          suppliersChanged ||
          supplierProductPricesChanged ||
          expensesChanged ||
          salesChanged ||
          purchasesChanged) {
        _warehouseStockCacheDirty = true;
        _accountLedgerCacheDirty = true;
      }
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return removed;
  }

  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() async {
    final problems = <String>[];
    final productIds = _products
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toSet();
    final supplierIds = _suppliers
        .where((item) => !item.isDeleted)
        .map((item) => item.id)
        .toSet();

    for (final price in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      if (!productIds.contains(price.productId)) {
        problems.add(
          'Supplier price ${price.id} references missing product ${price.productId}',
        );
      }
      if (!supplierIds.contains(price.supplierId)) {
        problems.add(
          'Supplier price ${price.id} references missing supplier ${price.supplierId}',
        );
      }
    }

    final activePriceKeys = <String>{};
    for (final price in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      final key = '${price.productId}::${price.supplierId}';
      if (!activePriceKeys.add(key)) {
        problems.add(
          'Duplicate supplier price for product ${price.productId} and supplier ${price.supplierId}',
        );
      }
    }

    for (final sale in _sales.where((item) => !item.isDeleted)) {
      if (sale.invoiceNo.trim().isEmpty) {
        problems.add('Sale ${sale.id} has no invoice number');
      }
      if (sale.items.isEmpty) {
        problems.add('Sale ${sale.invoiceNo} has no line items');
      }
      for (final item in sale.items) {
        if (!productIds.contains(item.productId)) {
          problems.add(
            'Sale ${sale.invoiceNo} references missing product ${item.productId}',
          );
        }
      }
      final movements = _stockMovements
          .where(
            (movement) =>
                movement.referenceId == sale.id && movement.type == 'sale',
          )
          .toList();
      if (sale.status != 'Cancelled' && movements.length < sale.items.length) {
        problems.add('Sale ${sale.invoiceNo} is missing stock movement(s)');
      }
    }

    for (final purchase in _purchases.where((item) => !item.isDeleted)) {
      if (purchase.items.isEmpty) {
        problems.add('Purchase ${purchase.id} has no line items');
      }
      for (final item in purchase.items) {
        if (!productIds.contains(item.productId)) {
          problems.add(
            'Purchase ${purchase.id} references missing product ${item.productId}',
          );
        }
      }
    }

    return BusinessDataIntegrityResult(
      ok: problems.isEmpty,
      message: problems.isEmpty
          ? 'Business data integrity check passed.'
          : problems.take(8).join('; '),
      problemCount: problems.length,
    );
  }

  Future<void> updateStoreProfile(StoreProfile profile) async {
    requirePermission(AppPermission.settingsManage);
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    _recordSyncChange(
      entityType: 'store_profile',
      entityId: 'store',
      operation: 'update',
      payload: profile.toJson(),
    );
    await _saveDirty(storeProfile: true, sync: true);
    notifyListeners();
  }

  void _validateProduct(Product product, {Product? previousProduct}) {
    if (product.name.trim().isEmpty ||
        product.code.trim().isEmpty ||
        product.category.trim().isEmpty) {
      throw ArgumentError('Product name, code, and category are required.');
    }
    if (!product.price.isFinite ||
        !product.cost.isFinite ||
        product.price < 0 ||
        product.cost < 0 ||
        product.stock < 0 ||
        product.lowStockThreshold < 0) {
      throw ArgumentError(
        'Product price, cost, stock, and low stock threshold must be zero or positive.',
      );
    }

    final normalizedCode = product.code.trim().toLowerCase();
    final normalizedBarcode = product.barcode.trim().toLowerCase();
    final previousCode = previousProduct?.code.trim().toLowerCase();
    final previousBarcode = previousProduct?.barcode.trim().toLowerCase();
    final codeChanged =
        previousProduct == null || normalizedCode != previousCode;
    final barcodeChanged =
        previousProduct == null || normalizedBarcode != previousBarcode;

    String? codeOwnerId;
    if (codeChanged) {
      codeOwnerId = _productIdByNormalizedCode[normalizedCode];
    } else {
      codeOwnerId = previousProduct.id;
    }
    String? barcodeOwnerId;
    if (barcodeChanged && normalizedBarcode.isNotEmpty) {
      barcodeOwnerId = _productIdByNormalizedBarcode[normalizedBarcode];
    } else {
      barcodeOwnerId = previousProduct?.id;
    }
    final duplicate = (codeOwnerId != null && codeOwnerId != product.id) ||
        (barcodeOwnerId != null && barcodeOwnerId != product.id);
    if (duplicate) {
      throw ArgumentError('Product code or barcode already exists.');
    }
  }

  String _generateUniqueProductCode({
    String? exceptProductId,
    Set<String>? reservedCodes,
  }) {
    final used = {
      ..._productIdByNormalizedCode.keys.map((value) => value.toUpperCase()),
      ...?reservedCodes,
    };
    var counter = _products.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }

  String get _invoiceDevicePrefix {
    final clean =
        _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (appIdentity.isHost) return 'H${clean.padRight(4, '0').substring(0, 4)}';
    return 'C${clean.padRight(4, '0').substring(0, 4)}';
  }

  int _invoiceSequenceFromNo(String invoiceNo) {
    final matches = RegExp(r'(\d+)').allMatches(invoiceNo).toList();
    if (matches.isEmpty) return 0;
    return int.tryParse(matches.last.group(1) ?? '') ?? 0;
  }

  String? _sqliteKeyForEntityType(String entityType) {
    switch (entityType) {
      case 'product':
        return _productsKey;
      case 'customer':
        return _customersKey;
      case 'supplier':
        return _suppliersKey;
      case 'supplier_product_price':
        return _supplierProductPricesKey;
      case 'sale':
        return _salesKey;
      case 'sale_quotation':
        return _saleQuotationsKey;
      case 'delivery_note':
        return _deliveryNotesKey;
      case 'bill_of_materials':
        return _billsOfMaterialsKey;
      case 'manufacturing_order':
        return _manufacturingOrdersKey;
      case 'purchase':
        return _purchasesKey;
      case 'inventory_count':
        return _inventoryCountsKey;
      case 'warehouse':
        return _warehousesKey;
      case 'expense':
        return _expensesKey;
      case 'stock_movement':
        return _stockMovementsKey;
      case 'account_transaction':
        return _accountTransactionsKey;
      case 'category':
        return _categoriesKey;
      case 'brand':
        return _brandsKey;
      case 'unit':
        return _unitsKey;
      case 'role':
        return _rolesKey;
      case 'user':
        return _usersKey;
    }
    return null;
  }

  void _rememberSqliteDirtyBusinessRow(
    String key,
    Map<String, dynamic> payload,
  ) {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    final id = payload['id']?.toString() ?? '';
    if (id.isEmpty) return;
    (_sqliteDirtyBusinessRows[key] ??= <String, Map<String, dynamic>>{})[id] =
        Map<String, dynamic>.from(payload);
  }

  Map<String, dynamic> _businessPayloadWithoutSyncEnvelope(
    Map<String, dynamic> payload,
  ) {
    final clean = Map<String, dynamic>.from(payload);
    clean.remove('_syncV2');
    return clean;
  }

  void _rememberRemoteSqliteBusinessRows(SyncChange change) {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;

    final businessKey = _sqliteKeyForEntityType(change.entityType);
    if (businessKey != null && change.payload.isNotEmpty) {
      _rememberSqliteDirtyBusinessRow(
        businessKey,
        _businessPayloadWithoutSyncEnvelope(change.payload),
      );
    }

    // Applying a remote stock movement mutates the related Product stock/cost
    // in memory as a side effect. Persist that Product row too; otherwise the
    // movement is visible only until restart when SQLite is authoritative.
    if (change.entityType == 'stock_movement') {
      final productId = change.payload['productId']?.toString() ?? '';
      if (productId.isNotEmpty) {
        final product = _findProductById(productId);
        if (product != null) {
          _rememberSqliteDirtyBusinessRow(_productsKey, product.toJson());
        }
      }
    }
  }

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    _traceSync('syncChange', 'enqueue_change', () {
      final now = DateTime.now();
      final identity = appIdentity;
      final changeId = _newSyncEnvelopeId(now, identity.isHost ? 'evt' : 'cmd');

      // Sync V2 bridge:
      // The existing SyncChange envelope is still kept for compatibility with
      // tests, LAN endpoints, and old installations, but every new local change
      // is explicitly tagged as either a Client DraftCommand or a Host
      // AuthoritativeEvent. Cloud/LAN transports can therefore enforce the new
      // Host-authoritative contract without guessing from endpoint names.
      final mutationId =
          '${_deviceId}_${now.microsecondsSinceEpoch}_${entityType}_${entityId}_$operation';
      final isHostEvent = identity.isHost;
      final requestId = isHostEvent ? '' : changeId;
      final eventId = isHostEvent ? changeId : '';
      final syncV2Meta = <String, dynamic>{
        'kind': isHostEvent ? 'authoritativeEvent' : 'draftCommand',
        'requestId': requestId,
        'eventId': eventId,
        'clientMutationId': mutationId,
        'sourceDeviceId': _deviceId,
        'sourceRole': identity.deviceRole.name,
        'transport': identity.transportType,
        'recordedAt': now.toIso8601String(),
      };
      final wrappedPayload = <String, dynamic>{
        ...payload,
        '_syncV2': syncV2Meta
      };

      final draftChange = SyncChange(
        id: changeId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        deviceId: _deviceId,
        createdAt: now,
        payload: wrappedPayload,
        storeId: identity.storeId,
        branchId: identity.branchId,
        storeEpoch: identity.storeEpoch,
        // Host is the only authority that may assign final ordering. Client
        // draft commands carry sequence 0 until the Host accepts and republishes
        // them as authoritative events.
        sequence: isHostEvent ? _nextSyncSequence() : 0,
      );
      final queued = _enqueueSyncChange(changeId, now);
      // If no sync transport is enabled by the current Sync settings, keep the
      // local audit envelope but mark it complete immediately. This prevents
      // Stress Lab/local-only usage from accumulating misleading pending LAN work
      // just because a legacy AppIdentity still says syncMode=lanOnly.
      final change = queued == null
          ? draftChange.copyWith(isSynced: true, syncedAt: now)
          : draftChange;
      _syncChanges.add(change);
      _sqliteDirtySyncChanges.add(change);
      final businessKey = _sqliteKeyForEntityType(entityType);
      if (businessKey != null) {
        _rememberSqliteDirtyBusinessRow(businessKey, payload);
      }
      if (queued != null) _sqliteDirtySyncQueue.add(queued);
    }, metadata: <String, Object?>{
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation,
    });
  }

  bool get _isLanClientConfigured {
    final raw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final mode = decoded['mode']?.toString() ?? '';
      final setupComplete = decoded['setupComplete'] as bool? ?? false;
      final hostModeEnabled = decoded['hostModeEnabled'] as bool? ?? false;
      return setupComplete && (mode == 'client' || !hostModeEnabled);
    } catch (_) {
      return false;
    }
  }

  bool get _isCloudClientConfigured {
    final raw = LocalDatabaseService.getString(_appIdentityKey);
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final identity = AppIdentity.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final base =
          LocalDatabaseService.getString('cloud_api_base_url')?.trim() ?? '';
      return identity.isClient &&
          identity.deviceId.trim().isNotEmpty &&
          identity.deviceToken.trim().isNotEmpty &&
          base.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _isLanHostConfigured {
    final raw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final mode = decoded['mode']?.toString() ?? '';
      final setupComplete = decoded['setupComplete'] as bool? ?? false;
      final hostModeEnabled = decoded['hostModeEnabled'] as bool? ?? false;
      return setupComplete && (mode == 'host' || hostModeEnabled);
    } catch (_) {
      return false;
    }
  }

  SyncQueueItem? _enqueueSyncChange(String changeId, DateTime now) {
    final identity = appIdentity;
    final activeTransport = identity.activeSyncTransportNormalized;
    final isLanClient =
        identity.isClient && activeTransport == 'lan' && _isLanClientConfigured;

    // Sync architecture v2: the Host is the only source of truth.
    // - Host devices publish accepted/authoritative changes to Cloud.
    // - LAN clients send drafts to the Host over LAN.
    // - Web/remote desktop clients cannot reach LAN directly, so they send drafts
    //   to a Cloud relay inbox. The Host later pulls that inbox, applies the
    //   changes, and republishes them as authoritative sync_events.
    final isLanHost = _isLanHostConfigured;
    final target = identity.isHost && identity.isCloudEnabled
        ? 'cloud'
        : isLanHost
            ? 'host'
            : isLanClient
                ? 'host'
                : (identity.isClient && activeTransport == 'cloud')
                    ? 'cloud_host'
                    : (identity.platform == AppPlatformType.web &&
                            activeTransport == 'cloud')
                        ? 'cloud_host'
                        : 'local';
    if (target == 'local') return null;
    final item = SyncQueueItem(
      id: '$changeId-$target',
      changeId: changeId,
      target: target,
      status: 'pending',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
    _syncQueue.add(item);
    return item;
  }

  T _withSyncMeta<T>(
    T item,
    DateTime now, {
    bool isCreate = false,
    bool clearDeletedAt = true,
  }) {
    final nextVersion = _readVersion(item) + (isCreate ? 0 : 1);
    final storeId = appIdentity.storeId;
    final branchId = appIdentity.branchId;
    if (item is Product) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_productsKey, updated.toJson());
      return updated as T;
    }
    if (item is Customer) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_customersKey, updated.toJson());
      return updated as T;
    }
    if (item is Supplier) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_suppliersKey, updated.toJson());
      return updated as T;
    }
    if (item is SupplierProductPrice) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        _supplierProductPricesKey,
        updated.toJson(),
      );
      return updated as T;
    }
    if (item is Expense) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_expensesKey, updated.toJson());
      return updated as T;
    }
    if (item is CatalogItem) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      return updated as T;
    }
    if (item is Sale) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_salesKey, updated.toJson());
      return updated as T;
    }
    if (item is SaleQuotation) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
      );
      _rememberSqliteDirtyBusinessRow(_saleQuotationsKey, updated.toJson());
      return updated as T;
    }
    if (item is DeliveryNote) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_deliveryNotesKey, updated.toJson());
      return updated as T;
    }
    if (item is BillOfMaterials) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_billsOfMaterialsKey, updated.toJson());
      return updated as T;
    }
    if (item is ManufacturingOrder) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        _manufacturingOrdersKey,
        updated.toJson(),
      );
      return updated as T;
    }
    if (item is Purchase) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(_purchasesKey, updated.toJson());
      return updated as T;
    }
    if (item is AccountTransaction) {
      final updated = item.copyWith(
        createdAt: isCreate ? now : item.createdAt,
        updatedAt: now,
        deviceId: _deviceId,
        syncStatus: 'pending',
        storeId: storeId,
        branchId: branchId,
        version: nextVersion,
        lastModifiedByDeviceId: _deviceId,
        clearDeletedAt: clearDeletedAt,
      );
      _rememberSqliteDirtyBusinessRow(
        _accountTransactionsKey,
        updated.toJson(),
      );
      return updated as T;
    }
    return item;
  }

  double _safeAccountAmount(double value) =>
      value.isFinite && value > 0 ? value : 0;

  Future<void> addOrUpdateAccountTransaction(
    AccountTransaction transaction,
  ) async {
    requirePermission(AppPermission.accountingManage);
    final now = DateTime.now();
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      throw ArgumentError(
        'Account transaction accountType must be customer or supplier.',
      );
    }
    if (normalized.accountId.trim().isEmpty) {
      throw ArgumentError('Account transaction accountId is required.');
    }
    if (normalized.debit == 0 && normalized.credit == 0) {
      throw ArgumentError('Account transaction amount is required.');
    }
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];
    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: index == -1 ? 'upsert' : 'update',
      payload: synced.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    await AccountingService.recordAccountPayment(synced);
    notifyListeners();
  }

  Future<void> deleteAccountTransaction(String id) async {
    requirePermission(AppPermission.accountingManage);
    final index = _accountTransactionIndexForId(id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<AccountTransaction>(
      _accountTransactions[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    final previous = _accountTransactions[index];
    _putAccountTransactionAtIndex(deleted, index);
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: deleted,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    await AccountingService.reverseEntryForReference(
      referenceType:
          deleted.isCustomer ? 'customer_payment' : 'supplier_payment',
      referenceId: deleted.id,
      reason: 'Account payment deleted',
      createdBy: _deviceId,
    );
    notifyListeners();
  }

  void _upsertAccountTransactionInternal(
    AccountTransaction transaction,
    DateTime now, {
    String operation = 'upsert',
  }) {
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      return;
    }
    if (normalized.accountId.trim().isEmpty) return;
    if (normalized.debit == 0 && normalized.credit == 0) return;
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];
    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: operation,
      payload: synced.toJson(),
    );
  }

  void _recordPurchaseLedger(Purchase purchase, DateTime now) {
    if (!purchase.isReceived ||
        purchase.isCancelled ||
        purchase.supplierId.trim().isEmpty) {
      return;
    }
    final total = purchase.subtotal;
    final paid = purchase.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${purchase.id}-purchase-invoice',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: purchase.date,
        type: 'purchaseInvoice',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: 0,
        credit: total,
        note: 'Purchase invoice ${purchase.purchaseNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'purchase_invoice',
    );
    if (paid > 0) {
      _upsertAccountTransactionInternal(
        AccountTransaction(
          id: '${purchase.id}-purchase-payment',
          accountType: 'supplier',
          accountId: purchase.supplierId,
          accountName: purchase.supplierName,
          date: purchase.date,
          type: 'paymentPaid',
          paymentMethod: purchase.paymentMethod,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          debit: paid,
          credit: 0,
          note: 'Payment for purchase ${purchase.purchaseNo}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        now,
        operation: 'purchase_payment',
      );
    }
  }

  void _recordPurchaseCancelLedger(
    Purchase purchase,
    DateTime now, {
    String reason = '',
    bool isReturn = false,
  }) {
    if (purchase.supplierId.trim().isEmpty) return;
    final total = purchase.items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    if (total <= 0) return;
    final paid = purchase.paidAmount.clamp(0, total).toDouble();
    final note = reason.trim().isEmpty
        ? (isReturn
            ? 'Purchase return ${purchase.purchaseNo}'
            : 'Purchase cancelled')
        : reason.trim();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn
            ? '${purchase.id}-purchase-return'
            : '${purchase.id}-purchase-cancel',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: now,
        type: isReturn ? 'purchaseReturn' : 'cancel',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: total,
        credit: 0,
        note: note,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'purchase_return' : 'purchase_cancel',
    );
    if (paid > 0) {
      _upsertAccountTransactionInternal(
        AccountTransaction(
          id: isReturn
              ? '${purchase.id}-purchase-return-payment-reversal'
              : '${purchase.id}-purchase-payment-reversal',
          accountType: 'supplier',
          accountId: purchase.supplierId,
          accountName: purchase.supplierName,
          date: now,
          type: 'paymentReversal',
          paymentMethod: purchase.paymentMethod,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          debit: 0,
          credit: paid,
          note: isReturn
              ? 'Refund/reversal of payment for returned purchase ${purchase.purchaseNo}'
              : 'Reversal of payment for cancelled purchase ${purchase.purchaseNo}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        now,
        operation: isReturn
            ? 'purchase_return_payment_reversal'
            : 'purchase_payment_reversal',
      );
    }
  }

  void _recordSaleLedger(Sale sale, DateTime now) {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal;
    final paid = sale.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${sale.id}-sale-invoice',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: sale.date,
        type: 'saleInvoice',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: total,
        credit: 0,
        currency: sale.invoiceCurrency,
        note: 'Sale invoice ${sale.invoiceNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'sale_invoice',
    );
    if (paid > 0) {
      final cashPart = sale.paymentMethod == 'Cash'
          ? paid
          : sale.cashReceivedAmount.clamp(0, paid).toDouble();
      final nonCashPart = (paid - cashPart).clamp(0, paid).toDouble();
      if (cashPart > 0) {
        _upsertAccountTransactionInternal(
          AccountTransaction(
            id: nonCashPart > 0
                ? '${sale.id}-sale-payment-cash'
                : '${sale.id}-sale-payment',
            accountType: 'customer',
            accountId: accountId,
            accountName: sale.customerName,
            date: sale.date,
            type: 'paymentReceived',
            paymentMethod: 'Cash',
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: 0,
            credit: cashPart,
            currency: sale.invoiceCurrency,
            note: 'Cash payment for sale ${sale.invoiceNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          now,
          operation: 'sale_payment_cash',
        );
      }
      if (nonCashPart > 0) {
        _upsertAccountTransactionInternal(
          AccountTransaction(
            id: cashPart > 0
                ? '${sale.id}-sale-payment-${sale.paymentMethod.toLowerCase()}'
                : '${sale.id}-sale-payment',
            accountType: 'customer',
            accountId: accountId,
            accountName: sale.customerName,
            date: sale.date,
            type: 'paymentReceived',
            paymentMethod: sale.paymentMethod,
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: 0,
            credit: nonCashPart,
            currency: sale.invoiceCurrency,
            note: 'Payment for sale ${sale.invoiceNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          now,
          operation: 'sale_payment',
        );
      }
    }
  }

  void _recordSaleCancelLedger(
    Sale sale,
    DateTime now, {
    bool isReturn = false,
  }) {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal > 0
        ? sale.invoiceTotal
        : ((sale.items.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                sale.discount)
            .clamp(0, double.infinity)
            .toDouble());
    if (total <= 0) return;
    final paid = sale.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn ? '${sale.id}-sale-return' : '${sale.id}-sale-cancel',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: now,
        type: isReturn ? 'saleReturn' : 'cancel',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: 0,
        credit: total,
        currency: sale.invoiceCurrency,
        note: isReturn ? 'Sale return ${sale.invoiceNo}' : 'Sale cancelled',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'sale_return' : 'sale_cancel',
    );
    if (paid > 0) {
      final cashPart = sale.paymentMethod == 'Cash'
          ? paid
          : sale.cashReceivedAmount.clamp(0, paid).toDouble();
      final nonCashPart = (paid - cashPart).clamp(0, paid).toDouble();
      if (cashPart > 0) {
        _upsertAccountTransactionInternal(
          AccountTransaction(
            id: isReturn
                ? (nonCashPart > 0
                    ? '${sale.id}-sale-return-payment-reversal-cash'
                    : '${sale.id}-sale-return-payment-reversal')
                : (nonCashPart > 0
                    ? '${sale.id}-sale-payment-reversal-cash'
                    : '${sale.id}-sale-payment-reversal'),
            accountType: 'customer',
            accountId: accountId,
            accountName: sale.customerName,
            date: now,
            type: 'paymentReversal',
            paymentMethod: 'Cash',
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: cashPart,
            credit: 0,
            currency: sale.invoiceCurrency,
            note: isReturn
                ? 'Refund/reversal of cash payment for returned sale ${sale.invoiceNo}'
                : 'Reversal of cash payment for cancelled sale ${sale.invoiceNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          now,
          operation: isReturn
              ? 'sale_return_payment_reversal_cash'
              : 'sale_payment_reversal_cash',
        );
      }
      if (nonCashPart > 0) {
        _upsertAccountTransactionInternal(
          AccountTransaction(
            id: isReturn
                ? (cashPart > 0
                    ? '${sale.id}-sale-return-payment-reversal-${sale.paymentMethod.toLowerCase()}'
                    : '${sale.id}-sale-return-payment-reversal')
                : (cashPart > 0
                    ? '${sale.id}-sale-payment-reversal-${sale.paymentMethod.toLowerCase()}'
                    : '${sale.id}-sale-payment-reversal'),
            accountType: 'customer',
            accountId: accountId,
            accountName: sale.customerName,
            date: now,
            type: 'paymentReversal',
            paymentMethod: sale.paymentMethod,
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: nonCashPart,
            credit: 0,
            currency: sale.invoiceCurrency,
            note: isReturn
                ? 'Refund/reversal of payment for returned sale ${sale.invoiceNo}'
                : 'Reversal of payment for cancelled sale ${sale.invoiceNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          now,
          operation: isReturn
              ? 'sale_return_payment_reversal'
              : 'sale_payment_reversal',
        );
      }
    }
  }

  void _recordExpenseLedger(Expense expense, DateTime now) {
    final accountId = expense.id.trim();
    if (accountId.isEmpty || expense.amount <= 0) return;
    final accountName =
        expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
    final currency = expense.originalCurrency.trim().isEmpty
        ? 'USD'
        : expense.originalCurrency.trim().toUpperCase();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-debit',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: expense.date,
        type: 'expense',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: expense.amount,
        credit: 0,
        currency: currency,
        note: 'Expense ${expense.title}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_post',
    );
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-credit',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: expense.date,
        type: 'paymentPaid',
        paymentMethod: 'Cash',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: 0,
        credit: expense.amount,
        currency: currency,
        note: 'Expense settlement ${expense.title}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_payment',
    );
  }

  void _reverseExpenseLedger(Expense expense, DateTime now,
      {String reason = ''}) {
    final accountId = expense.id.trim();
    if (accountId.isEmpty || expense.amount <= 0) return;
    final accountName =
        expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
    final currency = expense.originalCurrency.trim().isEmpty
        ? 'USD'
        : expense.originalCurrency.trim().toUpperCase();
    final noteSuffix =
        reason.trim().isEmpty ? 'cancelled expense' : reason.trim();
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-debit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'cancel',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: 0,
        credit: expense.amount,
        currency: currency,
        note: 'Reverse expense debit for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_debit',
    );
    _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-credit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'paymentReversal',
        paymentMethod: 'Cash',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: expense.amount,
        credit: 0,
        currency: currency,
        note: 'Reverse expense payment for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_payment',
    );
  }

  Product _markProductForSync(
    Product product,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _withSyncMeta<Product>(product, now, isCreate: isCreate);

  CatalogItem _markCatalogItemForSync(
    CatalogItem item,
    DateTime now, {
    bool isCreate = false,
  }) =>
      _withSyncMeta<CatalogItem>(item, now, isCreate: isCreate);

  void _ensureDefaultPriceLists() {
    if (_priceLists.any((item) => item.id == 'retail')) return;
    final now = DateTime.now();
    _priceLists.insert(
        0,
        PriceList(
            id: 'retail',
            name: 'Retail',
            code: 'retail',
            isDefault: true,
            createdAt: now,
            updatedAt: now));
    if (!_priceLists.any((item) => item.id == 'wholesale')) {
      _priceLists.add(PriceList(
          id: 'wholesale',
          name: 'Wholesale',
          code: 'wholesale',
          createdAt: now,
          updatedAt: now));
    }
  }

  String _productPriceLookupKey(
    String productId,
    String priceListId,
    String unitId,
  ) =>
      '$productId|$priceListId|$unitId';

  void _rebuildProductPriceLookupCache() {
    _productPriceByLookupKey.clear();
    for (final item in _productPrices) {
      if (!item.isActive) continue;
      _productPriceByLookupKey[_productPriceLookupKey(
        item.productId,
        item.priceListId,
        item.unitId,
      )] = item;
    }
  }

  void _rebuildProductCostLookupCache() {
    _productCostByProductId.clear();
    _productCostIndexByProductId.clear();
    for (var i = 0; i < _productCosts.length; i += 1) {
      final item = _productCosts[i];
      if (item.productId.trim().isEmpty) continue;
      _productCostByProductId[item.productId] = item;
      _productCostIndexByProductId[item.productId] = i;
    }
  }

  void _rebuildProductPricingLookupCaches() {
    _rebuildProductPriceLookupCache();
    _rebuildProductCostLookupCache();
  }

  void _ensureProductPricingLookupCaches() {
    if (_productPriceByLookupKey.isEmpty && _productPrices.isNotEmpty) {
      _rebuildProductPriceLookupCache();
    }
    if (_productCostByProductId.isEmpty && _productCosts.isNotEmpty) {
      _rebuildProductCostLookupCache();
    }
  }

  void _removeProductPricingLookupEntries(String productId) {
    _productPriceByLookupKey.removeWhere(
      (_, value) => value.productId == productId,
    );
    _productCostByProductId.remove(productId);
  }

  void _ensureDefaultProductPriceEntries({Product? product}) {
    _ensureDefaultPriceLists();
    _ensureProductPricingLookupCaches();
    final retailId = defaultPriceList.id;
    final now = DateTime.now();
    final productsToCheck = product == null
        ? _products.where((item) => !item.isDeleted)
        : <Product>[product];
    for (final current in productsToCheck) {
      if (current.isDeleted) continue;
      final key = '${current.id}|$retailId|base';
      if (!_productPriceByLookupKey.containsKey(key)) {
        final price = ProductPrice(
          id: 'pp_${current.id}_${retailId}_base',
          productId: current.id,
          priceListId: retailId,
          unitId: 'base',
          baseCurrencyCode: current.originalCurrency,
          baseAmount: current.originalPrice,
          createdAt: current.createdAt,
          updatedAt: now,
        );
        _productPrices.add(price);
        _productPriceByLookupKey[key] = price;
      }
      for (final unit in current.saleUnits) {
        final unitKey = '${current.id}|$retailId|${unit.id}';
        if (_productPriceByLookupKey.containsKey(unitKey)) continue;
        final price = ProductPrice(
          id: 'pp_${current.id}_${retailId}_${unit.id}',
          productId: current.id,
          priceListId: retailId,
          unitId: unit.id,
          baseCurrencyCode: unit.originalCurrency,
          baseAmount: unit.originalPrice,
          createdAt: current.createdAt,
          updatedAt: now,
        );
        _productPrices.add(price);
        _productPriceByLookupKey[unitKey] = price;
      }
    }
  }

  Future<void> setDefaultProductBasePrice(
      {required String productId,
      required String unitId,
      required double amount,
      required String currencyCode}) async {
    final productExists = _products.any((item) => item.id == productId);
    requirePermission(productExists
        ? AppPermission.productsEdit
        : AppPermission.productsCreate);
    _ensureDefaultPriceLists();
    final now = DateTime.now();
    final priceListId = defaultPriceList.id;
    final index = _productPrices.indexWhere((item) =>
        item.productId == productId &&
        item.priceListId == priceListId &&
        item.unitId == unitId);
    final price = ProductPrice(
      id: index == -1
          ? 'pp_${productId}_${priceListId}_${unitId}_${now.microsecondsSinceEpoch}'
          : _productPrices[index].id,
      productId: productId,
      priceListId: priceListId,
      unitId: unitId,
      baseCurrencyCode: currencyCode.toUpperCase(),
      baseAmount: amount,
      createdAt: index == -1 ? now : _productPrices[index].createdAt,
      updatedAt: now,
    );
    if (index == -1) {
      _productPrices.add(price);
    } else {
      _productPrices[index] = price;
    }
    _productPriceByLookupKey[
        _productPriceLookupKey(productId, priceListId, unitId)] = price;
    await LocalDatabaseService.setString(_priceListsKey,
        jsonEncode(_priceLists.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_productPricesKey,
        jsonEncode(_productPrices.map((item) => item.toJson()).toList()));
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> setProductPriceOverride({
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) async {
    requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (productPriceId.trim().isEmpty || normalizedCurrency.isEmpty) {
      throw ArgumentError('Product price and currency are required.');
    }
    final now = DateTime.now();
    final index = _productPriceOverrides.indexWhere(
      (item) =>
          item.productPriceId == productPriceId &&
          item.currencyCode == normalizedCurrency,
    );
    final override = ProductPriceOverride(
      id: index == -1
          ? 'ppo_${productPriceId}_${normalizedCurrency}_${now.microsecondsSinceEpoch}'
          : _productPriceOverrides[index].id,
      productPriceId: productPriceId,
      currencyCode: normalizedCurrency,
      amount: amount,
      mode: mode,
      isActive: isActive,
      createdAt: index == -1 ? now : _productPriceOverrides[index].createdAt,
      updatedAt: now,
    );
    if (index == -1) {
      _productPriceOverrides.add(override);
    } else {
      _productPriceOverrides[index] = override;
    }
    await LocalDatabaseService.setString(
        _productPriceOverridesKey,
        jsonEncode(
            _productPriceOverrides.map((item) => item.toJson()).toList()));
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> removeProductPriceOverride(
      String productPriceId, String currencyCode) async {
    requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    final index = _productPriceOverrides.indexWhere(
      (item) =>
          item.productPriceId == productPriceId &&
          item.currencyCode == normalizedCurrency,
    );
    if (index == -1) return;
    _productPriceOverrides[index] = _productPriceOverrides[index]
        .copyWith(isActive: false, updatedAt: DateTime.now());
    await LocalDatabaseService.setString(
        _productPriceOverridesKey,
        jsonEncode(
            _productPriceOverrides.map((item) => item.toJson()).toList()));
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  void _ensureProductCostEntries({Product? product}) {
    _ensureProductPricingLookupCaches();
    final now = DateTime.now();
    final productsToCheck = product == null
        ? _products.where((item) => !item.isDeleted)
        : <Product>[product];
    for (final current in productsToCheck) {
      if (current.isDeleted) continue;
      if (_productCostByProductId.containsKey(current.id)) continue;
      final cost = ProductCost(
        productId: current.id,
        averageCost: _safeUsdCost(current),
        lastCost: _safeUsdCost(current),
        currencyCode: 'USD',
        createdAt: current.createdAt,
        updatedAt: now,
      );
      _productCostIndexByProductId[current.id] = _productCosts.length;
      _productCosts.add(cost);
      _productCostByProductId[current.id] = cost;
    }
  }

  void _ensureCostingMethodHistory() {
    if (_costingMethodHistory.isNotEmpty) return;
    final now = DateTime.now();
    _costingMethodHistory.add(CostingMethodHistory(
      id: 'costing_${now.microsecondsSinceEpoch}',
      method: _inventoryCostingMethod,
      effectiveFrom: now,
      reason: 'Initial costing method',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> setInventoryCostingMethod(InventoryCostingMethod method,
      {String reason = ''}) async {
    requirePermission(AppPermission.productsEdit);
    if (_inventoryCostingMethod == method && _costingMethodHistory.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_costingMethodHistory.isNotEmpty) {
      final openIndex =
          _costingMethodHistory.indexWhere((item) => item.effectiveTo == null);
      if (openIndex != -1) {
        _costingMethodHistory[openIndex] = _costingMethodHistory[openIndex]
            .copyWith(effectiveTo: now, updatedAt: now);
      }
    }
    _inventoryCostingMethod = method;
    _costingMethodHistory.add(CostingMethodHistory(
      id: 'costing_${now.microsecondsSinceEpoch}',
      method: method,
      effectiveFrom: now,
      reason: reason.trim(),
      createdAt: now,
      updatedAt: now,
    ));
    await LocalDatabaseService.setString(
        _inventoryCostingMethodKey, method.code);
    await LocalDatabaseService.setString(
        _costingMethodHistoryKey,
        jsonEncode(
            _costingMethodHistory.map((item) => item.toJson()).toList()));
    _touchDataRevisions(products: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  ProductCost _upsertProductCostFromPurchase({
    required Product product,
    required double receivedQty,
    required double baseUnitCost,
    required DateTime now,
  }) {
    _ensureProductCostEntries();
    final current = _productCostByProductId[product.id] ??
        ProductCost(
          productId: product.id,
          averageCost: _safeUsdCost(product),
          lastCost: _safeUsdCost(product),
          currencyCode: 'USD',
          createdAt: now,
          updatedAt: now,
        );
    final stockBefore = max(0, product.stock);
    final stockAfter = stockBefore + receivedQty;
    final averageCost = stockAfter <= 0
        ? baseUnitCost
        : ((stockBefore * current.averageCost) + (receivedQty * baseUnitCost)) /
            stockAfter;
    final updated = current.copyWith(
      averageCost: averageCost,
      lastCost: baseUnitCost,
      currencyCode: 'USD',
      updatedAt: now,
    );
    final index = _productCostIndexByProductId[product.id];
    if (index == null || index < 0 || index >= _productCosts.length) {
      final fallbackIndex =
          _productCosts.indexWhere((item) => item.productId == product.id);
      if (fallbackIndex == -1) {
        _productCostIndexByProductId[product.id] = _productCosts.length;
        _productCosts.add(updated);
      } else {
        _productCosts[fallbackIndex] = updated;
        _productCostIndexByProductId[product.id] = fallbackIndex;
      }
    } else {
      _productCosts[index] = updated;
    }
    _productCostByProductId[product.id] = updated;
    return updated;
  }

  void _addInventoryCostLayerFromPurchase({
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required double quantity,
    required double unitCost,
    required DateTime now,
  }) {
    if (quantity <= 0) return;
    final id = '${purchase.id}-$lineIndex-${item.productId}-cost-layer';
    if (_inventoryCostLayerIndexById.containsKey(id)) return;
    _inventoryCostLayerIndexById[id] = _inventoryCostLayers.length;
    _inventoryCostLayers.add(InventoryCostLayer(
      id: id,
      productId: item.productId,
      productName: item.productName,
      quantityReceived: quantity,
      quantityRemaining: quantity,
      unitCost: unitCost,
      currencyCode: 'USD',
      exchangeRate: 1,
      purchaseId: purchase.id,
      purchaseItemId: '$lineIndex',
      sourceType: 'purchase',
      sourceId: purchase.id,
      createdAt: now,
      updatedAt: now,
    ));
  }

  void _addInventoryCostLayerFromStockIncrease({
    required String id,
    required Product product,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required DateTime now,
  }) {
    if (quantity <= 0 || !product.trackStock) return;
    if (_inventoryCostLayerIndexById.containsKey(id)) return;
    _inventoryCostLayerIndexById[id] = _inventoryCostLayers.length;
    _inventoryCostLayers.add(InventoryCostLayer(
      id: id,
      productId: product.id,
      productName: product.name,
      quantityReceived: quantity,
      quantityRemaining: quantity,
      unitCost: unitCost,
      currencyCode: 'USD',
      exchangeRate: 1,
      purchaseId: '',
      purchaseItemId: '',
      sourceType: sourceType,
      sourceId: sourceId,
      createdAt: now,
      updatedAt: now,
    ));
  }

  bool _purchaseHasConsumedCostLayers(String purchaseId) {
    return _inventoryCostLayers.any((layer) =>
        layer.purchaseId == purchaseId &&
        layer.quantityReceived - layer.quantityRemaining > 0.000001);
  }

  InventoryCostResult _resolveCostForSaleItem(SaleItem item, DateTime now) {
    final product = _findProductById(item.productId);
    final cost = productCostFor(item.productId);
    if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0),
      );
    }
    if (_inventoryCostingMethod == InventoryCostingMethod.fifo) {
      var qtyToConsume = item.effectiveBaseQuantity;
      final consumptions = <InventoryCostLayerConsumption>[];
      final indexes = <int>[];
      for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
        final layer = _inventoryCostLayers[i];
        if (layer.productId == item.productId &&
            !layer.isClosed &&
            layer.quantityRemaining > 0) {
          indexes.add(i);
        }
      }
      indexes.sort((a, b) => _inventoryCostLayers[a]
          .createdAt
          .compareTo(_inventoryCostLayers[b].createdAt));
      for (final index in indexes) {
        if (qtyToConsume <= 0) break;
        final layer = _inventoryCostLayers[index];
        final consumed = min(qtyToConsume, layer.quantityRemaining);
        if (consumed <= 0) continue;
        consumptions.add(InventoryCostLayerConsumption(
          layerId: layer.id,
          quantity: consumed,
          unitCost: layer.unitCost,
          currencyCode: layer.currencyCode,
        ));
        final remaining = layer.quantityRemaining - consumed;
        _inventoryCostLayers[index] = layer.copyWith(
          quantityRemaining: remaining,
          isClosed: remaining <= 0,
          updatedAt: now,
        );
        qtyToConsume -= consumed;
      }
      if (qtyToConsume > 0) {
        final fallbackCost = cost.averageCost > 0
            ? cost.averageCost
            : (cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0));
        if (fallbackCost > 0) {
          consumptions.add(InventoryCostLayerConsumption(
            layerId:
                'negative_stock_${item.productId}_${now.microsecondsSinceEpoch}',
            quantity: qtyToConsume,
            unitCost: fallbackCost,
            currencyCode: 'USD',
          ));
        }
      }
      final totalQty =
          item.effectiveBaseQuantity <= 0 ? 0 : item.effectiveBaseQuantity;
      final totalCost =
          consumptions.fold<double>(0, (sum, entry) => sum + entry.totalCost);
      final unitCost = totalQty <= 0 ? 0.0 : totalCost / totalQty;
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: unitCost,
        consumptions: consumptions,
      );
    }
    return InventoryCostResult(
      method: _inventoryCostingMethod,
      unitCost:
          cost.averageCost > 0 ? cost.averageCost : (product?.usdCost ?? 0),
    );
  }

  void _restoreInventoryCostLayersFromSaleItem(SaleItem item, DateTime now) {
    if (item.costLayerConsumptions.isEmpty) return;
    for (final consumption in item.costLayerConsumptions) {
      final index = _inventoryCostLayers
          .indexWhere((layer) => layer.id == consumption.layerId);
      if (index == -1) continue;
      final layer = _inventoryCostLayers[index];
      final remaining = layer.quantityRemaining + consumption.quantity;
      _inventoryCostLayers[index] = layer.copyWith(
        quantityRemaining: remaining,
        isClosed: false,
        updatedAt: now,
      );
    }
  }

  void _closeInventoryCostLayersForPurchase(String purchaseId, DateTime now) {
    for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
      final layer = _inventoryCostLayers[i];
      if (layer.purchaseId != purchaseId) continue;
      _inventoryCostLayers[i] = layer.copyWith(
        quantityRemaining: 0,
        isClosed: true,
        updatedAt: now,
      );
    }
  }

  void _indexProductAt(int index, Product product, {Product? previousProduct}) {
    _productIndexById[product.id] = index;
    if (previousProduct != null) {
      final previousCode = previousProduct.code.trim().toLowerCase();
      if (previousCode.isNotEmpty &&
          _productIdByNormalizedCode[previousCode] == previousProduct.id) {
        _productIdByNormalizedCode.remove(previousCode);
      }
      final previousBarcode = previousProduct.barcode.trim().toLowerCase();
      if (previousBarcode.isNotEmpty &&
          _productIdByNormalizedBarcode[previousBarcode] ==
              previousProduct.id) {
        _productIdByNormalizedBarcode.remove(previousBarcode);
      }
    }
    if (product.isDeleted) return;
    final code = product.code.trim().toLowerCase();
    if (code.isNotEmpty) _productIdByNormalizedCode[code] = product.id;
    final barcode = product.barcode.trim().toLowerCase();
    if (barcode.isNotEmpty) {
      _productIdByNormalizedBarcode[barcode] = product.id;
    }
  }

  void _unindexProduct(Product product) {
    final index = _productIndexById[product.id];
    if (index != null && index >= 0 && index < _products.length) {
      _productIndexById[product.id] = index;
    }
    final code = product.code.trim().toLowerCase();
    if (code.isNotEmpty && _productIdByNormalizedCode[code] == product.id) {
      _productIdByNormalizedCode.remove(code);
    }
    final barcode = product.barcode.trim().toLowerCase();
    if (barcode.isNotEmpty &&
        _productIdByNormalizedBarcode[barcode] == product.id) {
      _productIdByNormalizedBarcode.remove(barcode);
    }
  }

  void _indexCustomerAt(int index, Customer customer,
      {Customer? previousCustomer}) {
    _customerIndexById[customer.id] = index;
    if (previousCustomer != null) {
      final previousName = previousCustomer.name.trim().toLowerCase();
      if (previousName.isNotEmpty &&
          _customerIdByNormalizedName[previousName] == previousCustomer.id) {
        _customerIdByNormalizedName.remove(previousName);
      }
    }
    if (customer.isDeleted) return;
    final normalizedName = customer.name.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      _customerIdByNormalizedName[normalizedName] = customer.id;
    }
  }

  void _indexSupplierAt(int index, Supplier supplier,
      {Supplier? previousSupplier}) {
    _supplierIndexById[supplier.id] = index;
    if (previousSupplier != null) {
      final previousName = previousSupplier.name.trim().toLowerCase();
      if (previousName.isNotEmpty &&
          _supplierIdByNormalizedName[previousName] == previousSupplier.id) {
        _supplierIdByNormalizedName.remove(previousName);
      }
    }
    if (supplier.isDeleted) return;
    final normalizedName = supplier.name.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      _supplierIdByNormalizedName[normalizedName] = supplier.id;
    }
  }

  Future<void> addOrUpdateProduct(Product product) async {
    final section = 'product.addOrUpdate';
    final index = _productIndexById[product.id];
    final exists = index != null;
    requirePermission(
      exists ? AppPermission.productsEdit : AppPermission.productsCreate,
    );
    final now = DateTime.now();
    final normalizedProduct = product.code.trim().isEmpty
        ? product.copyWith(
            code: _generateUniqueProductCode(exceptProductId: product.id),
          )
        : product;

    final isCreate = index == null;
    final existingIndex = index ?? -1;
    final previousProduct = isCreate ? null : _products[existingIndex];
    _traceSync(section, 'validate', () {
      _validateProduct(normalizedProduct, previousProduct: previousProduct);
    }, metadata: <String, Object?>{
      'productId': normalizedProduct.id,
      'isCreate': isCreate
    });
    final syncedProduct = _traceSyncResult<Product>(
      section,
      'mark_sync',
      () => _markProductForSync(
        normalizedProduct,
        now,
        isCreate: isCreate,
      ),
      metadata: <String, Object?>{
        'productId': normalizedProduct.id,
        'isCreate': isCreate
      },
    );
    if (isCreate) {
      _products.add(syncedProduct);
      _indexProductAt(_products.length - 1, syncedProduct);
    } else {
      final existingIndex = index;
      _products[existingIndex] = syncedProduct;
      _indexProductAt(
        existingIndex,
        syncedProduct,
        previousProduct: previousProduct,
      );
    }
    _traceSync(section, 'ensure_price_entries', () {
      _ensureDefaultProductPriceEntries(product: syncedProduct);
    }, metadata: <String, Object?>{'productId': syncedProduct.id});
    _traceSync(section, 'ensure_cost_entries', () {
      _ensureProductCostEntries(product: syncedProduct);
    }, metadata: <String, Object?>{'productId': syncedProduct.id});
    _traceSync(section, 'ensure_costing_history', _ensureCostingMethodHistory);
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'product',
        entityId: syncedProduct.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedProduct.toJson(),
      );
    }, metadata: <String, Object?>{
      'productId': syncedProduct.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(products: true, sync: true),
        metadata: <String, Object?>{
          'productId': syncedProduct.id,
          'isCreate': isCreate
        });
    unawaited(
      AppLogger.info(
        area: 'products',
        action: isCreate ? 'create_product' : 'update_product',
        message: isCreate
            ? 'Product created successfully.'
            : 'Product updated successfully.',
        details:
            'productId=${syncedProduct.id} code=${syncedProduct.code} name=${syncedProduct.name}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'product',
        entityId: syncedProduct.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Product created' : 'Product updated',
        details: jsonEncode(syncedProduct.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'products',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  bool isProductReferenced(String productId) {
    if (productId.trim().isEmpty) return false;
    final usedInSales = _sales.any(
      (sale) =>
          !sale.isDeleted &&
          sale.items.any((item) => item.productId == productId),
    );
    if (usedInSales) return true;
    final usedInPurchases = _purchases.any(
      (purchase) =>
          !purchase.isDeleted &&
          purchase.items.any((item) => item.productId == productId),
    );
    if (usedInPurchases) return true;
    return _stockMovements.any((movement) => movement.productId == productId);
  }

  Future<void> deleteProduct(String id) async {
    requirePermission(AppPermission.productsDelete);
    final index = _productIndexById[id];
    if (index == null) return;
    if (isProductReferenced(id)) {
      throw StateError(
        'Cannot delete a product that is used by sales, purchases, or stock movements. Deactivate it instead.',
      );
    }
    final now = DateTime.now();
    final previousProduct = _products[index];
    final deletedProduct = _withSyncMeta<Product>(
      previousProduct.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _products[index] = deletedProduct;
    _recordSyncChange(
      entityType: 'product',
      entityId: id,
      operation: 'delete',
      payload: deletedProduct.toJson(),
    );
    _unindexProduct(previousProduct);
    _removeProductPricingLookupEntries(id);
    final affectedPrices = _softDeleteSupplierProductPrices(
      productId: id,
      now: now,
      reason: 'Product deleted',
    );
    await _saveDirty(
      products: true,
      productDerivedData: false,
      supplierProductPrices: affectedPrices > 0,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'products',
        action: 'delete_product',
        message: 'Product deleted successfully.',
        details: 'productId=$id affectedSupplierProductPrices=$affectedPrices',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'product',
        entityId: id,
        action: 'delete',
        summary: 'Product deleted',
        details: jsonEncode(deletedProduct.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'products',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  int _softDeleteSupplierProductPrices({
    String? productId,
    String? supplierId,
    required DateTime now,
    String reason = '',
  }) {
    var affected = 0;
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (item.isDeleted) continue;
      final matchesProduct = productId == null || item.productId == productId;
      final matchesSupplier =
          supplierId == null || item.supplierId == supplierId;
      if (!matchesProduct || !matchesSupplier) continue;
      final updated = _withSyncMeta<SupplierProductPrice>(
        item.copyWith(
          deletedAt: now,
          notes: reason.trim().isEmpty
              ? item.notes
              : [
                  item.notes,
                  reason,
                ].where((part) => part.trim().isNotEmpty).join(' — '),
        ),
        now,
        clearDeletedAt: false,
      );
      _supplierProductPrices[i] = updated;
      _recordSyncChange(
        entityType: 'supplier_product_price',
        entityId: updated.id,
        operation: 'delete',
        payload: updated.toJson(),
      );
      affected++;
    }
    return affected;
  }

  Future<void> addOrUpdateCustomer(Customer customer) async {
    final section = 'customer.addOrUpdate';
    requirePermission(AppPermission.customersManage);
    if (customer.name.trim().isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final normalizedName = customer.name.trim();
    final activeDuplicateId =
        _customerIdByNormalizedName[normalizedName.toLowerCase()];
    final activeDuplicate = activeDuplicateId != null &&
        activeDuplicateId != customer.id &&
        activeDuplicateId != walkInCustomerId;
    if (activeDuplicate) {
      throw ArgumentError(
        'Customer name already exists on this device. Sync duplicates will be reported as conflicts.',
      );
    }
    final now = DateTime.now();
    final incoming = (customer.id == walkInCustomerId ||
            normalizedName.toLowerCase() == walkInCustomerName.toLowerCase())
        ? _withSyncMeta<Customer>(walkInCustomer, now, isCreate: false)
        : _withSyncMeta<Customer>(
            customer.copyWith(name: normalizedName),
            now,
            isCreate: false,
          );
    final index = _customerIndexById[incoming.id];

    final isCreate = index == null;
    final baseCustomer = isCreate
        ? incoming
        : (() {
            final existingIndex = index;
            return incoming.copyWith(
              id: _customers[existingIndex].id,
              clearDeletedAt: true,
            );
          })();
    final syncedCustomer = _withSyncMeta<Customer>(
      baseCustomer,
      now,
      isCreate: isCreate,
      clearDeletedAt: true,
    );
    if (isCreate) {
      _customers.add(syncedCustomer);
      _indexCustomerAt(_customers.length - 1, syncedCustomer);
    } else {
      final existingIndex = index;
      final previousCustomer = _customers[existingIndex];
      _customers[existingIndex] = syncedCustomer;
      _indexCustomerAt(
        existingIndex,
        syncedCustomer,
        previousCustomer: previousCustomer,
      );
    }
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'customer',
        entityId: syncedCustomer.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedCustomer.toJson(),
      );
    }, metadata: <String, Object?>{
      'customerId': syncedCustomer.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(customers: true, sync: true),
        metadata: <String, Object?>{
          'customerId': syncedCustomer.id,
          'isCreate': isCreate
        });
    unawaited(
      AppLogger.info(
        area: 'customers',
        action: isCreate ? 'create_customer' : 'update_customer',
        message: isCreate
            ? 'Customer created successfully.'
            : 'Customer updated successfully.',
        details: 'customerId=${syncedCustomer.id} name=${syncedCustomer.name}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'customer',
        entityId: syncedCustomer.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Customer created' : 'Customer updated',
        details: jsonEncode(syncedCustomer.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'customers',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    requirePermission(AppPermission.customersManage);
    final index = _customerIndexById[id];
    if (index == null) return;
    final previousCustomer = _customers[index];
    final customer = previousCustomer;
    final isWalkIn = customer.id == walkInCustomerId ||
        customer.name.trim().toLowerCase() == walkInCustomerName.toLowerCase();
    if (isWalkIn) return;
    final now = DateTime.now();
    final deletedCustomer = _withSyncMeta<Customer>(
      previousCustomer.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _customers[index] = deletedCustomer;
    _recordSyncChange(
      entityType: 'customer',
      entityId: id,
      operation: 'delete',
      payload: deletedCustomer.toJson(),
    );
    _indexCustomerAt(
      index,
      deletedCustomer,
      previousCustomer: previousCustomer,
    );
    await _saveDirty(customers: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'customers',
        action: 'delete_customer',
        message: 'Customer deleted successfully.',
        details: 'customerId=$id',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'customer',
        entityId: id,
        action: 'delete',
        summary: 'Customer deleted',
        details: jsonEncode(_customers[index].toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'customers',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<void> addOrUpdateSupplier(Supplier supplier) async {
    final section = 'supplier.addOrUpdate';
    requirePermission(AppPermission.suppliersManage);
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final normalizedName = supplier.name.trim().toLowerCase();
    final duplicateId = _supplierIdByNormalizedName[normalizedName];
    final duplicate = duplicateId != null && duplicateId != supplier.id;
    if (duplicate) {
      throw ArgumentError(
        'Supplier name already exists on this device. Sync duplicates will be reported as conflicts.',
      );
    }
    final now = DateTime.now();
    final cleanedSupplier = supplier.copyWith(name: supplier.name.trim());
    final index = _supplierIndexById[cleanedSupplier.id];
    final isCreate = index == null;
    final syncedSupplier = _withSyncMeta<Supplier>(
      cleanedSupplier,
      now,
      isCreate: isCreate,
    );
    if (isCreate) {
      _suppliers.add(syncedSupplier);
      _indexSupplierAt(_suppliers.length - 1, syncedSupplier);
    } else {
      final existingIndex = index;
      final previousSupplier = _suppliers[existingIndex];
      _suppliers[existingIndex] = syncedSupplier;
      _indexSupplierAt(
        existingIndex,
        syncedSupplier,
        previousSupplier: previousSupplier,
      );
    }
    _traceSync(section, 'record_sync_change', () {
      _recordSyncChange(
        entityType: 'supplier',
        entityId: syncedSupplier.id,
        operation: isCreate ? 'create' : 'update',
        payload: syncedSupplier.toJson(),
      );
    }, metadata: <String, Object?>{
      'supplierId': syncedSupplier.id,
      'isCreate': isCreate
    });
    await _traceAsync(
        section, 'save_dirty', () => _saveDirty(suppliers: true, sync: true),
        metadata: <String, Object?>{
          'supplierId': syncedSupplier.id,
          'isCreate': isCreate
        });
    unawaited(
      AppLogger.info(
        area: 'suppliers',
        action: isCreate ? 'create_supplier' : 'update_supplier',
        message: isCreate
            ? 'Supplier created successfully.'
            : 'Supplier updated successfully.',
        details: 'supplierId=${syncedSupplier.id} name=${syncedSupplier.name}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'supplier',
        entityId: syncedSupplier.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Supplier created' : 'Supplier updated',
        details: jsonEncode(syncedSupplier.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'suppliers',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteSupplier(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _supplierIndexById[id];
    if (index == null) return;
    final now = DateTime.now();
    final previousSupplier = _suppliers[index];
    final deletedSupplier = _withSyncMeta<Supplier>(
      previousSupplier.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _suppliers[index] = deletedSupplier;
    _recordSyncChange(
      entityType: 'supplier',
      entityId: id,
      operation: 'delete',
      payload: deletedSupplier.toJson(),
    );
    _indexSupplierAt(index, deletedSupplier,
        previousSupplier: previousSupplier);
    final affectedPrices = _softDeleteSupplierProductPrices(
      supplierId: id,
      now: now,
      reason: 'Supplier deleted',
    );
    await _saveDirty(
      suppliers: true,
      supplierProductPrices: affectedPrices > 0,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateCategory(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_categories, item);
    _recordSyncChange(
      entityType: 'category',
      entityId: syncedItem.id,
      operation: _categories
                      .where((existing) => existing.id == syncedItem.id)
                      .length ==
                  1 &&
              syncedItem.createdAt == syncedItem.updatedAt
          ? 'create'
          : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(categories: true, sync: true);
    notifyListeners();
  }

  Future<void> addOrUpdateBrand(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_brands, item);
    _recordSyncChange(
      entityType: 'brand',
      entityId: syncedItem.id,
      operation:
          syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(brands: true, sync: true);
    notifyListeners();
  }

  Future<void> addOrUpdateUnit(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_units, item);
    _recordSyncChange(
      entityType: 'unit',
      entityId: syncedItem.id,
      operation:
          syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update',
      payload: syncedItem.toJson(),
    );
    await _saveDirty(units: true, sync: true);
    notifyListeners();
  }

  CatalogItem _addOrUpdateCatalogItem(
    List<CatalogItem> list,
    CatalogItem item,
  ) {
    if (item.nameEn.trim().isEmpty && item.nameAr.trim().isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalizedEn = item.nameEn.trim().toLowerCase();
    final normalizedAr = item.nameAr.trim().toLowerCase();
    final duplicate = list.any((existing) {
      if (existing.id == item.id || existing.isDeleted) return false;
      return (normalizedEn.isNotEmpty &&
              existing.nameEn.trim().toLowerCase() == normalizedEn) ||
          (normalizedAr.isNotEmpty &&
              existing.nameAr.trim().toLowerCase() == normalizedAr);
    });
    if (duplicate) throw ArgumentError('This name already exists.');
    final index = list.indexWhere((existing) => existing.id == item.id);
    final now = DateTime.now();
    final isCreate = index == -1;
    final syncedItem = _markCatalogItemForSync(item, now, isCreate: isCreate);
    if (isCreate) {
      list.add(syncedItem);
    } else {
      list[index] = syncedItem;
    }
    return syncedItem;
  }

  String _catalogReferenceValue(CatalogItem item) =>
      item.code.trim().isNotEmpty ? item.code.trim() : item.nameEn.trim();

  bool _catalogItemMatchesValue(CatalogItem item, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return item.code.trim().toLowerCase() == normalized ||
        item.nameEn.trim().toLowerCase() == normalized ||
        item.nameAr.trim().toLowerCase() == normalized;
  }

  int productsUsingCatalogItem(String type, CatalogItem item) {
    if (type != 'category' && type != 'unit') return 0;
    return _products.where((product) {
      if (product.isDeleted) return false;
      final value = type == 'category' ? product.category : product.unit;
      return _catalogItemMatchesValue(item, value);
    }).length;
  }

  Future<void> replaceAndDeleteCatalogItem({
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) async {
    requirePermission(AppPermission.catalogManage);
    if (type != 'category' && type != 'unit') {
      throw ArgumentError('Unsupported catalog type.');
    }
    final list = type == 'category' ? _categories : _units;
    final activeItems = list.where((entry) => !entry.isDeleted).toList();
    if (activeItems.length <= 1) {
      throw StateError('At least one item must remain.');
    }
    final index = list.indexWhere((entry) => entry.id == item.id);
    if (index == -1 || list[index].isDeleted) return;

    final usageCount = productsUsingCatalogItem(type, item);
    if (usageCount > 0) {
      if (replacement == null || replacement.id == item.id) {
        throw StateError('A replacement item is required.');
      }
      if (!activeItems.any((entry) => entry.id == replacement.id)) {
        throw StateError('Replacement item was not found.');
      }
    }

    final now = DateTime.now();
    var productsChanged = false;
    if (usageCount > 0) {
      final replacementValue = _catalogReferenceValue(replacement!);
      if (replacementValue.trim().isEmpty) {
        throw StateError('Replacement item has no usable value.');
      }
      for (var i = 0; i < _products.length; i++) {
        final product = _products[i];
        if (product.isDeleted) continue;
        final currentValue =
            type == 'category' ? product.category : product.unit;
        if (!_catalogItemMatchesValue(item, currentValue)) continue;
        final updatedProduct = _markProductForSync(
          type == 'category'
              ? product.copyWith(category: replacementValue)
              : product.copyWith(unit: replacementValue),
          now,
        );
        _products[i] = updatedProduct;
        _recordSyncChange(
          entityType: 'product',
          entityId: updatedProduct.id,
          operation: 'update',
          payload: updatedProduct.toJson(),
        );
        productsChanged = true;
      }
    }

    final deletedItem = _withSyncMeta<CatalogItem>(
      list[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    list[index] = deletedItem;
    _recordSyncChange(
      entityType: type,
      entityId: deletedItem.id,
      operation: 'delete',
      payload: deletedItem.toJson(),
    );

    await _saveDirty(
      products: productsChanged,
      categories: type == 'category',
      units: type == 'unit',
      sync: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateExpense(Expense expense) async {
    requirePermission(AppPermission.expensesManage);
    if (expense.title.trim().isEmpty ||
        expense.category.trim().isEmpty ||
        !expense.amount.isFinite ||
        expense.amount <= 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final now = DateTime.now();
    final index = _expenseIndexForId(expense.id);
    final isCreate = index == -1;
    if (!isCreate) {
      final current = _expenses[index];
      if (current.isPosted) {
        throw StateError(
          'Posted expenses cannot be edited. Cancel them first.',
        );
      }
      if (current.isCancelled) {
        throw StateError('Cancelled expenses cannot be edited.');
      }
    }
    final normalized = expense.copyWith(
      status: isCreate ? 'Draft' : expense.status,
    );
    final syncedExpense = _withSyncMeta<Expense>(
      normalized,
      now,
      isCreate: isCreate,
    );
    _putExpenseAtIndex(syncedExpense, isCreate ? _expenses.length : index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: syncedExpense.id,
      operation: isCreate ? 'create' : 'update',
      payload: syncedExpense.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'expenses',
        action: isCreate ? 'create_expense' : 'update_expense',
        message: isCreate
            ? 'Expense created successfully.'
            : 'Expense updated successfully.',
        details:
            'expenseId=${syncedExpense.id} title=${syncedExpense.title} amount=${syncedExpense.amount}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'expense',
        entityId: syncedExpense.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Expense created' : 'Expense updated',
        details: jsonEncode(syncedExpense.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _activeUser?.fullName ?? _activeUser?.username ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'expenses',
        isImportant: true,
      ),
    );
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> postExpense(String id) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenseIndexForId(id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isPosted || expense.isCancelled) return;
    final now = DateTime.now();
    final posted = _withSyncMeta<Expense>(
      expense.copyWith(status: 'Posted'),
      now,
    );
    _expenses[index] = posted;
    _recordExpenseLedger(posted, now);
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'post',
      payload: posted.toJson(),
    );
    await _saveDirty(expenses: true, accountTransactions: true, sync: true);
    _scheduleExpenseAccounting(posted);
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> deleteDraftExpense(String id) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (expense.isPosted) {
      throw StateError('Posted expenses cannot be deleted. Cancel them first.');
    }
    if (expense.isCancelled) {
      throw StateError(
        'Cancelled expenses require permanent delete permission.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(
      expense.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _putExpenseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> cancelExpense(String id, {String reason = ''}) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenseIndexForId(id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isCancelled) return;
    if (!expense.isPosted) {
      throw StateError(
        'Only posted expenses can be cancelled. Delete draft expenses instead.',
      );
    }
    final now = DateTime.now();
    final cancelled = _withSyncMeta<Expense>(
      expense.copyWith(
        status: 'Cancelled',
        cancelReason: reason.trim(),
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
      ),
      now,
    );
    _putExpenseAtIndex(cancelled, index);
    _reverseExpenseLedger(
      cancelled,
      now,
      reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
    );
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _waitForPendingExpenseAccounting(expense.id);
    await AccountingService.reverseEntryForReference(
      referenceType: 'expense',
      referenceId: expense.id,
      reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
      createdBy: _deviceId,
    );
    await _saveDirty(expenses: true, accountTransactions: true, sync: true);
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> permanentlyDeleteCancelledExpense(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (!expense.isCancelled) {
      throw StateError('Only cancelled expenses can be permanently deleted.');
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(
      expense.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _putExpenseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'permanent_delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> deleteExpense(String id) => deleteDraftExpense(id);

  String get _purchaseDevicePrefix => _deviceId.isEmpty
      ? 'LOCAL'
      : _deviceId
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase()
          .padRight(4, '0')
          .substring(0, 4);

  int _loadPurchaseCounter() {
    final raw = LocalDatabaseService.getString(_purchaseCounterKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) throw ArgumentError('Warehouse name is required.');
    _ensureDefaultWarehouse();
    if (_warehouses.any(
      (item) =>
          !item.isDeleted &&
          item.name.toLowerCase() == cleanedName.toLowerCase(),
    )) {
      throw ArgumentError('Warehouse already exists.');
    }
    final now = DateTime.now();
    final warehouse = Warehouse(
      id: now.microsecondsSinceEpoch.toString(),
      name: cleanedName,
      code: code.trim(),
      location: location.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    _warehouses.add(warehouse);
    _rememberSqliteDirtyBusinessRow(_warehousesKey, warehouse.toJson());
    _recordSyncChange(
      entityType: 'warehouse',
      entityId: warehouse.id,
      operation: 'create',
      payload: warehouse.toJson(),
    );
    await _saveDirty(warehouses: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'inventory',
        action: 'create_warehouse',
        message: 'Warehouse created successfully.',
        details: 'warehouseId=${warehouse.id} name=${warehouse.name}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'warehouse',
        entityId: warehouse.id,
        action: 'create',
        summary: 'Warehouse created',
        details: jsonEncode(warehouse.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'inventory',
        isImportant: true,
      ),
    );
    notifyListeners();
    return warehouse;
  }

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be positive.');
    }
    _ensureDefaultWarehouse();
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    final productIndex = _productIndexById[productId];
    if (productIndex == null) throw ArgumentError('Product not found.');
    final product = _products[productIndex];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final fromWarehouse = _warehouses.firstWhere(
      (item) => item.id == fromWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Source warehouse not found.'),
    );
    final toWarehouse = _warehouses.firstWhere(
      (item) => item.id == toWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Destination warehouse not found.'),
    );
    final available = stockForWarehouse(productId, fromWarehouseId);
    if (available < quantity) {
      throw StateError('Not enough stock in ${fromWarehouse.name}.');
    }
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-out',
        productId: productId,
        productName: product.name,
        type: 'warehouse_transfer_out',
        quantity: -quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer to ${toWarehouse.name}',
        notes: notes.trim(),
        warehouseId: fromWarehouse.id,
        warehouseName: fromWarehouse.name,
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-in',
        productId: productId,
        productName: product.name,
        type: 'warehouse_transfer_in',
        quantity: quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer from ${fromWarehouse.name}',
        notes: notes.trim(),
        warehouseId: toWarehouse.id,
        warehouseName: toWarehouse.name,
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    await _saveDirty(stockMovements: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'inventory',
        action: 'transfer_stock',
        message: 'Stock transferred successfully.',
        details:
            'productId=$productId from=$fromWarehouseId to=$toWarehouseId quantity=$quantity',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'stock_movement',
        entityId: transferId,
        action: 'transfer',
        summary: 'Stock transferred',
        details: jsonEncode(<String, Object?>{
          'productId': productId,
          'fromWarehouseId': fromWarehouseId,
          'toWarehouseId': toWarehouseId,
          'quantity': quantity,
          'notes': notes,
        }),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'inventory',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
  }) async {
    requirePermission(AppPermission.suppliersManage);
    if (items.isEmpty) {
      throw ArgumentError('Purchase must contain at least one item.');
    }
    for (final item in items) {
      if (item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitCost < 0) {
        throw ArgumentError('Invalid purchase item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    _purchaseCounter += 1;
    final now = DateTime.now();
    final purchaseTotal = items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final normalizedPaymentStatus =
        paymentStatus.trim().toLowerCase() == 'credit'
            ? 'credit'
            : paymentStatus.trim().toLowerCase() == 'partial'
                ? 'partial'
                : 'paid';
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final normalizedPaidAmount = normalizedPaymentStatus == 'paid'
        ? purchaseTotal
        : normalizedPaymentStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, purchaseTotal).toDouble();
    final purchase = Purchase(
      id: 'purchase_${_purchaseDevicePrefix}_${_purchaseCounter.toString().padLeft(6, '0')}',
      purchaseNo:
          'PO-$_purchaseDevicePrefix-${_purchaseCounter.toString().padLeft(6, '0')}',
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      date: now,
      status: receiveNow ? 'Received' : 'Draft',
      items: items,
      note: note,
      paymentStatus: normalizedPaymentStatus,
      paymentMethod: normalizedPaymentMethod,
      paidAmount: normalizedPaidAmount,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _putPurchaseAtIndex(purchase, _purchases.length);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: purchase.id,
      operation: 'create',
      payload: purchase.toJson(),
    );
    if (receiveNow) {
      _applyPurchaseStock(purchase, now);
      _recordPurchaseLedger(purchase, now);
    }
    await _saveDirty(
      purchases: true,
      products: receiveNow,
      productDerivedData: receiveNow,
      stockMovements: receiveNow,
      accountTransactions: receiveNow,
      purchaseCounter: true,
      sync: true,
    );
    if (receiveNow) {
      _schedulePurchaseAccounting(purchase);
    }
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'create_purchase',
        message: 'Purchase created successfully.',
        details:
            'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} total=$purchaseTotal receiveNow=$receiveNow',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: purchase.id,
        action: 'create',
        summary: 'Purchase created',
        details: jsonEncode(purchase.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
    return purchase;
  }

  Future<void> receivePurchase(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isReceived || purchase.isCancelled) return;
    final now = DateTime.now();
    final received = _withSyncMeta<Purchase>(
      purchase.copyWith(status: 'Received'),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(received, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: received.id,
      operation: 'receive',
      payload: received.toJson(),
    );
    _applyPurchaseStock(received, now);
    _recordPurchaseLedger(received, now);
    await _saveDirty(
      purchases: true,
      products: true,
      productDerivedData: true,
      stockMovements: true,
      accountTransactions: true,
      sync: true,
    );
    _schedulePurchaseAccounting(received);
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'receive_purchase',
        message: 'Purchase received successfully.',
        details: 'purchaseId=${received.id} purchaseNo=${received.purchaseNo}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: received.id,
        action: 'receive',
        summary: 'Purchase received',
        details: jsonEncode(received.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  Future<void> deleteDraftPurchase(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) return;
    if (purchase.isReceived) {
      throw StateError(
        'Received purchase invoices cannot be deleted. Cancel them first.',
      );
    }
    if (purchase.isCancelled) {
      throw StateError(
        'Cancelled purchase invoices require permanent delete permission.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Purchase>(
      purchase.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    if (index != -1) _putPurchaseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'delete_purchase',
        message: 'Draft purchase deleted successfully.',
        details: 'purchaseId=$id purchaseNo=${purchase.purchaseNo}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'delete',
        summary: 'Draft purchase deleted',
        details: jsonEncode(deleted.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  Future<void> permanentlyDeleteCancelledPurchase(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) return;
    if (purchase.status.toLowerCase() != 'cancelled') {
      throw StateError(
        'Only cancelled purchase invoices can be permanently deleted.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Purchase>(
      purchase.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    if (index != -1) _putPurchaseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'permanent_delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'permanent_delete_purchase',
        message: 'Cancelled purchase permanently deleted.',
        details: 'purchaseId=$id purchaseNo=${purchase.purchaseNo}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'permanent_delete',
        summary: 'Cancelled purchase permanently deleted',
        details: jsonEncode(deleted.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be returned. Delete draft invoices instead.',
      );
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-return',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_return',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
            unitCost: item.unitCostPerBase,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          recordSync: true,
        );
      }
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final returned = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Returned',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
        note: 'Returned on ${now.toIso8601String()}',
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(returned, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'return',
      payload: returned.toJson(),
    );
    _recordPurchaseCancelLedger(purchase, now, reason: reason, isReturn: true);
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'return_purchase',
        message: 'Purchase returned successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'return',
        summary: 'Purchase returned',
        details: jsonEncode(returned.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be cancelled. Delete draft invoices instead.',
      );
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && purchase.isReceived && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-cancel',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_cancel',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason:
                reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
            unitCost: item.unitCostPerBase,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          recordSync: true,
        );
      }
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final cancelled = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Cancelled',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(cancelled, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    _recordPurchaseCancelLedger(purchase, now, reason: reason);
    await _waitForPendingPurchaseAccounting(purchase.id);
    await AccountingService.reverseEntryForReference(
      referenceType: 'purchase',
      referenceId: purchase.id,
      reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
      createdBy: _deviceId,
    );
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'cancel_purchase',
        message: 'Purchase cancelled successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'cancel',
        summary: 'Purchase cancelled',
        details: jsonEncode(cancelled.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

  String _actorName() => _activeUser?.fullName.trim().isNotEmpty == true
      ? _activeUser!.fullName.trim()
      : (_activeUser?.username ?? currentRole);

  double _stockAt(String productId, DateTime at) {
    final productIndex = _productIndexById[productId];
    var stock = productIndex == null ? 0.0 : _products[productIndex].stock;
    for (final movement in _stockMovements) {
      if (movement.productId == productId && movement.date.isAfter(at)) {
        stock -= movement.quantity;
      }
    }
    return stock;
  }

  int movementCountAfterInventoryLine(InventoryCountLine line) {
    final countedAt = line.countedAt;
    if (countedAt == null) return 0;
    return _stockMovements
        .where(
          (movement) =>
              movement.productId == line.productId &&
              movement.date.isAfter(countedAt) &&
              movement.type != 'count_adjustment',
        )
        .length;
  }

  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (activeInventoryCountSession != null) {
      throw StateError('There is already an open inventory count session.');
    }
    final now = DateTime.now();
    final warehouse = defaultWarehouse;
    final session = InventoryCountSession(
      id: now.microsecondsSinceEpoch.toString(),
      countNo: 'CNT-${now.microsecondsSinceEpoch}',
      createdAt: now,
      createdBy: _actorName(),
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      notes: notes.trim(),
      lines: _products
          .where((product) => product.trackStock && !product.isDeleted)
          .map(
            (product) => InventoryCountLine(
              productId: product.id,
              productName: product.name,
              productCode: product.code,
              snapshotStock: product.stock,
            ),
          )
          .toList(),
    );
    _inventoryCounts.add(session);
    _rememberSqliteDirtyBusinessRow(_inventoryCountsKey, session.toJson());
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
    return session;
  }

  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (countedQty < 0) {
      throw ArgumentError('Counted quantity cannot be negative.');
    }
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be edited.');
    }
    final lineIndex = session.lines.indexWhere(
      (line) => line.productId == productId,
    );
    if (lineIndex == -1) {
      throw ArgumentError('Product is not part of this count session.');
    }
    final now = DateTime.now();
    final lines = List<InventoryCountLine>.from(session.lines);
    lines[lineIndex] = lines[lineIndex].copyWith(
      countedQty: countedQty,
      countedAt: now,
      countedBy: _actorName(),
      note: note.trim(),
    );
    _inventoryCounts[sessionIndex] = session.copyWith(
      lines: lines,
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      _inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

  Future<void> approveInventoryCount(String sessionId) async {
    requirePermission(AppPermission.productsEdit);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be approved.');
    }
    final countedLines = session.lines.where((line) => line.isCounted).toList();
    if (countedLines.isEmpty) {
      throw StateError('No counted products to approve.');
    }
    final now = DateTime.now();
    var productDerivedData = false;
    for (final line in countedLines) {
      final productIndex = _productIndexById[line.productId];
      if (productIndex == null) continue;
      final product = _products[productIndex];
      if (!product.trackStock) continue;
      final theoreticalAtCount = _stockAt(
        line.productId,
        line.countedAt ?? session.createdAt,
      );
      final delta =
          (line.countedQty ?? theoreticalAtCount) - theoreticalAtCount;
      if (delta.abs() < 0.000001) continue;
      _products[productIndex] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock + delta),
        now,
      );
      if (delta > 0) {
        final cost = productCostFor(product.id);
        _addInventoryCostLayerFromStockIncrease(
          id: '${session.id}-${line.productId}-count-layer',
          product: product,
          quantity: delta,
          unitCost:
              cost.averageCost > 0 ? cost.averageCost : _safeUsdCost(product),
          sourceType: 'inventory_count',
          sourceId: session.id,
          now: now,
        );
        productDerivedData = true;
      }
      _addStockMovement(
        StockMovement(
          id: '${session.id}-${line.productId}-count-adjustment',
          productId: line.productId,
          productName: line.productName,
          type: 'count_adjustment',
          quantity: delta,
          date: now,
          referenceId: session.id,
          referenceNo: session.countNo,
          reason: 'Inventory count adjustment',
          adjustmentCategory:
              delta < 0 ? 'stock_count_shortage' : 'stock_count_overage',
          notes:
              'Counted at ${line.countedAt?.toIso8601String() ?? session.createdAt.toIso8601String()}. Theoretical at count: $theoreticalAtCount. Counted: ${line.countedQty}.',
          unitCost: product.usdCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }
    _inventoryCounts[sessionIndex] = session.copyWith(
      status: 'approved',
      approvedAt: now,
      approvedBy: _actorName(),
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      _inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(
      products: true,
      productDerivedData: productDerivedData,
      stockMovements: true,
      inventoryCounts: true,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> cancelInventoryCount(String sessionId) async {
    requirePermission(AppPermission.productsEdit);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) return;
    final now = DateTime.now();
    _inventoryCounts[sessionIndex] = session.copyWith(
      status: 'cancelled',
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      _inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

  Future<void> reviewAutoCorrection(
    String movementId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    final index = _stockMovements.indexWhere(
      (movement) => movement.id == movementId,
    );
    if (index == -1) throw ArgumentError('Stock movement not found.');
    final movement = _stockMovements[index];
    if (movement.type != 'auto_correction') {
      throw StateError('Only automatic corrections can be reviewed here.');
    }
    if (movement.isReviewed) return;
    final now = DateTime.now();
    final reviewer = _activeUser?.fullName.trim().isNotEmpty == true
        ? _activeUser!.fullName.trim()
        : (_activeUser?.username ?? currentRole);
    final updated = movement.copyWith(
      reviewedAt: now,
      reviewedBy: reviewer,
      reviewNote: note.trim(),
      updatedAt: now,
      syncStatus: 'pending',
      version: movement.version + 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _putStockMovementAtIndex(updated, index);
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: updated.id,
      operation: 'review',
      payload: updated.toJson(),
    );
    await _saveDirty(stockMovements: true, sync: true);
    notifyListeners();
  }

  Future<void> adjustStock({
    required String productId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (quantityDelta == 0) return;
    final index = _productIndexById[productId];
    if (index == null) throw ArgumentError('Product not found.');
    final now = DateTime.now();
    final product = _products[index];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    _products[index] = _withSyncMeta<Product>(
      product.copyWith(stock: product.stock + quantityDelta),
      now,
    );
    _addStockMovement(
      StockMovement(
        id: '${now.microsecondsSinceEpoch}-$productId-adjustment',
        productId: productId,
        productName: product.name,
        type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
        quantity: quantityDelta,
        date: now,
        referenceId: productId,
        referenceNo: product.code,
        reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
        adjustmentCategory: adjustmentCategory.trim().isEmpty
            ? 'other'
            : adjustmentCategory.trim(),
        notes: notes.trim(),
        evidenceRef: evidenceRef.trim(),
        unitCost: product.usdCost,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    await _saveDirty(
      products: true,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
    notifyListeners();
  }

  void _applyPurchaseStock(Purchase purchase, DateTime now) {
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final index = _productIndexById[item.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final receivedQty = item.baseQuantity;
      final newStock = product.stock + receivedQty;
      final baseUnitCost = item.unitCostPerBase;
      final productCost = _upsertProductCostFromPurchase(
        product: product,
        receivedQty: receivedQty,
        baseUnitCost: baseUnitCost,
        now: now,
      );
      _addInventoryCostLayerFromPurchase(
        purchase: purchase,
        item: item,
        lineIndex: lineIndex,
        quantity: receivedQty,
        unitCost: baseUnitCost,
        now: now,
      );
      final appliedCost =
          _inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost
              ? productCost.lastCost
              : productCost.averageCost;
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(
          stock: newStock,
          cost: appliedCost,
          usdCost: appliedCost,
          originalCost: appliedCost,
          costCurrency: 'USD',
          costExchangeRateAtEntry: storeProfile.usdToLbpRate,
        ),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${purchase.id}-$lineIndex-${item.productId}-purchase-receive',
          productId: item.productId,
          productName: item.productName,
          type: 'purchase_receive',
          quantity: item.baseQuantity,
          date: now,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          reason: 'Purchase received',
          unitCost: item.unitCostPerBase,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }
  }

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) {
    final index = _stockMovementIndexForId(movement.id);
    if (index != -1) return;
    _putStockMovementAtIndex(movement, _stockMovements.length);
    if (recordSync) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.type,
        payload: movement.toJson(),
      );
    }
  }

  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (name.trim().isEmpty) throw ArgumentError('BOM name is required.');
    if (outputQuantity <= 0) {
      throw ArgumentError('Output quantity must be greater than zero.');
    }
    if (components.isEmpty) {
      throw ArgumentError('BOM must contain at least one component.');
    }
    final output = _findProductById(outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final cleanedComponents = <BillOfMaterialsLine>[];
    for (final component in components) {
      if (component.quantity <= 0) {
        throw ArgumentError('Component quantity must be greater than zero.');
      }
      if (component.productId == outputProductId) {
        throw ArgumentError(
          'Output product cannot be used as a component in the same BOM.',
        );
      }
      final product = _findProductById(component.productId);
      if (product == null) {
        throw ArgumentError('Component product was not found.');
      }
      cleanedComponents.add(
        component.copyWith(
          productName: product.name,
          unitCost: _safeUsdCost(product),
        ),
      );
    }
    final now = DateTime.now();
    final bom = _withSyncMeta<BillOfMaterials>(
      BillOfMaterials(
        id: '${now.microsecondsSinceEpoch}-bom',
        name: name.trim(),
        outputProductId: output.id,
        outputProductName: output.name,
        outputQuantity: outputQuantity,
        components: cleanedComponents,
        notes: notes.trim(),
      ),
      now,
      isCreate: true,
    );
    _billsOfMaterials.add(bom);
    _recordSyncChange(
      entityType: 'bill_of_materials',
      entityId: bom.id,
      operation: 'create',
      payload: bom.toJson(),
    );
    await _saveDirty(billsOfMaterials: true, sync: true);
    notifyListeners();
    return bom;
  }

  Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String warehouseId = '',
    String notes = '',
  }) async {
    requirePermission(AppPermission.productsEdit);
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final bom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final factor = quantity / bom.outputQuantity;
    final warehouse = warehouseId.trim().isEmpty
        ? defaultWarehouse
        : warehouses.firstWhere(
            (item) => item.id == warehouseId,
            orElse: () => defaultWarehouse,
          );
    for (final component in bom.components) {
      final product = _findProductById(component.productId);
      if (product == null || !product.trackStock) continue;
      final requiredQty = component.quantity * factor;
      if (product.stock < requiredQty) {
        throw ArgumentError(
          'Insufficient stock for ${product.name}. Required: $requiredQty, available: ${product.stock}.',
        );
      }
    }
    final now = DateTime.now();
    final order = _withSyncMeta<ManufacturingOrder>(
      ManufacturingOrder(
        id: '${now.microsecondsSinceEpoch}-mfg',
        orderNo: 'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
        bomId: bom.id,
        bomName: bom.name,
        outputProductId: output.id,
        outputProductName: output.name,
        quantity: quantity,
        notes: notes.trim(),
        date: now,
      ),
      now,
      isCreate: true,
    );

    for (var lineIndex = 0; lineIndex < bom.components.length; lineIndex += 1) {
      final component = bom.components[lineIndex];
      final index = _productIndexById[component.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final usedQty = component.quantity * factor;
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - usedQty),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-$lineIndex-${component.productId}-manufacturing-consume',
          productId: component.productId,
          productName: product.name,
          type: 'manufacturing_consume',
          quantity: -usedQty,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing component consumption',
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          unitCost: _safeUsdCost(product),
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    var productDerivedData = false;
    final outputIndex = _productIndexById[output.id];
    if (outputIndex != null && output.trackStock) {
      final producedCost = bom.unitCost;
      _products[outputIndex] = _withSyncMeta<Product>(
        output.copyWith(
          stock: output.stock + quantity,
          cost: producedCost,
          usdCost: producedCost,
          originalCost: producedCost,
          costCurrency: 'USD',
          costExchangeRateAtEntry: storeProfile.usdToLbpRate,
        ),
        now,
      );
      _addInventoryCostLayerFromStockIncrease(
        id: '${order.id}-${output.id}-manufacturing-layer',
        product: output,
        quantity: quantity,
        unitCost: producedCost,
        sourceType: 'manufacturing_output',
        sourceId: order.id,
        now: now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-${output.id}-manufacturing-output',
          productId: output.id,
          productName: output.name,
          type: 'manufacturing_output',
          quantity: quantity,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing finished goods output',
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          unitCost: producedCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
      productDerivedData = true;
    }

    _manufacturingOrders.add(order);
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'complete',
      payload: order.toJson(),
    );
    await _saveDirty(
      products: true,
      productDerivedData: productDerivedData,
      stockMovements: true,
      manufacturingOrders: true,
      sync: true,
    );
    notifyListeners();
    return order;
  }

  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) async {
    requirePermission(AppPermission.salesCreate);
    if (items.isEmpty) {
      throw ArgumentError('Quotation must contain at least one item.');
    }
    final cleanedDiscount =
        discount.isFinite ? discount.clamp(0, double.infinity).toDouble() : 0.0;
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid quotation item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final now = DateTime.now();
    final quotation = SaleQuotation(
      id: now.microsecondsSinceEpoch.toString(),
      quotationNo:
          'QTN-$_invoiceDevicePrefix-${(saleQuotations.length + 1).toString().padLeft(6, '0')}',
      customerName: customerName.trim().isEmpty
          ? walkInCustomerName
          : customerName.trim(),
      customerId:
          customerId.trim().isEmpty ? walkInCustomerId : customerId.trim(),
      date: now,
      validUntil: validUntil,
      status: 'Draft',
      items: items,
      discount: cleanedDiscount,
      invoiceCurrency: invoiceCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _saleQuotations.add(quotation);
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: quotation.id,
      operation: 'create',
      payload: quotation.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return quotation;
  }

  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) async {
    requirePermission(AppPermission.salesCreate);
    final index = _saleQuotations.indexWhere((item) => item.id == quotationId);
    if (index == -1) throw ArgumentError('Quotation not found.');
    final quotation = _saleQuotations[index];
    if (quotation.isDeleted) throw StateError('Quotation is deleted.');
    if (quotation.isConverted) {
      throw StateError('Quotation is already converted.');
    }
    final sale = await createSale(
      customerName: quotation.customerName,
      customerId: quotation.customerId,
      items: quotation.items,
      discount: quotation.discount,
      originalDiscount: quotation.discount,
      invoiceCurrency: quotation.invoiceCurrency,
      paymentCurrency: quotation.invoiceCurrency,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
    );
    final now = DateTime.now();
    final updated = _withSyncMeta<SaleQuotation>(
      quotation.copyWith(
        status: 'Converted',
        convertedSaleId: sale.id,
        updatedAt: now,
      ),
      now,
    );
    _saleQuotations[index] = updated;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: updated.id,
      operation: 'convert',
      payload: updated.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return sale;
  }

  Future<void> deleteSaleQuotation(String id) async {
    requirePermission(AppPermission.salesCancel);
    final index = _saleQuotations.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<SaleQuotation>(
      _saleQuotations[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _saleQuotations[index] = deleted;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
  }

  DeliveryNote? deliveryNoteForSale(String saleId) {
    _ensureDeliveryNoteLookupCache();
    return _cachedDeliveryNoteBySaleId?[saleId];
  }

  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.salesCreate);
    final saleIndex = _sales.indexWhere((item) => item.id == saleId);
    final sale =
        saleIndex == -1 ? await _saleByIdFromSqlite(saleId) : _sales[saleIndex];
    if (sale == null) throw ArgumentError('Sale not found.');
    if (sale.isDeleted) throw StateError('Sale is deleted.');
    if (sale.isCancelled) {
      throw StateError(
        'Cannot create a delivery note for a cancelled or returned sale.',
      );
    }
    final existing = deliveryNoteForSale(saleId);
    if (existing != null) return existing;
    final now = DateTime.now();
    final deliveryNote = DeliveryNote(
      id: '${now.microsecondsSinceEpoch}-delivery',
      deliveryNo:
          'DLV-$_invoiceDevicePrefix-${(_deliveryNotes.where((item) => !item.isDeleted).length + 1).toString().padLeft(6, '0')}',
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerName: sale.customerName,
      customerId: sale.customerId,
      date: now,
      status: 'Draft',
      items: sale.items,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _deliveryNotes.add(deliveryNote);
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: deliveryNote.id,
      operation: 'create',
      payload: deliveryNote.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
    return deliveryNote;
  }

  Future<void> markDeliveryNoteDelivered(String id) async {
    requirePermission(AppPermission.salesCreate);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Delivery note not found.');
    final current = _deliveryNotes[index];
    if (current.isDeleted || current.isDelivered) return;
    final now = DateTime.now();
    final updated = _withSyncMeta<DeliveryNote>(
      current.copyWith(status: 'Delivered', deliveredAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = updated;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'deliver',
      payload: updated.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> deleteDeliveryNote(String id) async {
    requirePermission(AppPermission.salesCancel);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<DeliveryNote>(
      _deliveryNotes[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = deleted;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<Sale> createSale({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String discountCurrency = 'USD',
    double discountExchangeRateAtEntry = 0,
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
    String invoiceCurrency = 'USD',
    String paymentCurrency = 'USD',
    double? exchangeRateAtPayment,
    double? paidAmount,
    double? cashReceivedAmount,
    double? paidAmountInPaymentCurrency,
    double? cashReceivedAmountInPaymentCurrency,
  }) async {
    requirePermission(AppPermission.salesCreate);
    if (items.isEmpty) {
      throw ArgumentError('Sale must contain at least one item.');
    }

    final double cleanedDiscount = discount.isFinite ? discount : 0.0;
    if (cleanedDiscount < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }

    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }

    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid sale item values.');
      }
      final product = _findProductById(item.productId);
      if (product == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }

    final now = DateTime.now();
    final saleItems = items.map((item) {
      final resolvedCost = item.unitCost > 0
          ? InventoryCostResult(
              method: _inventoryCostingMethod,
              unitCost: item.unitCost,
            )
          : _resolveCostForSaleItem(item, now);
      return SaleItem(
        productId: item.productId,
        productName: item.productName,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        unitName: item.unitName,
        baseQuantity: item.effectiveBaseQuantity,
        conversionToBase: item.conversionToBase,
        unitCost: resolvedCost.unitCost,
        costingMethodAtSale: resolvedCost.method,
        costCurrency: resolvedCost.currencyCode,
        costExchangeRate: 1,
        costLayerConsumptions: resolvedCost.consumptions,
      );
    }).toList();

    final saleTotal =
        (saleItems.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                cleanedDiscount)
            .clamp(0, double.infinity)
            .toDouble();
    String normalizeConfiguredCurrency(String value, [String? fallback]) {
      final normalized = value.trim().toUpperCase();
      final fallbackCurrency =
          (fallback ?? storeProfile.baseCurrency).toUpperCase();
      if (normalized.isEmpty) return fallbackCurrency;
      return storeProfile.currencies.any(
              (item) => item.isActive && item.code.toUpperCase() == normalized)
          ? normalized
          : fallbackCurrency;
    }

    final baseCurrency =
        normalizeConfiguredCurrency(storeProfile.baseCurrency, 'USD');
    final normalizedInvoiceCurrency =
        normalizeConfiguredCurrency(invoiceCurrency, baseCurrency);
    final normalizedPaymentCurrency =
        normalizeConfiguredCurrency(paymentCurrency, normalizedInvoiceCurrency);
    final invoiceRate = normalizedInvoiceCurrency == baseCurrency
        ? 1.0
        : exchangeRate(baseCurrency, normalizedInvoiceCurrency, storeProfile,
            effectiveAt: now);
    final exchangeRateAtPaymentValue = exchangeRateAtPayment;
    final safePaymentRate = exchangeRateAtPaymentValue != null &&
            exchangeRateAtPaymentValue > 0
        ? exchangeRateAtPaymentValue
        : exchangeRate(
            normalizedPaymentCurrency, normalizedInvoiceCurrency, storeProfile,
            effectiveAt: now);
    final rawSaleTotalInInvoiceCurrency = convertCurrency(
      saleTotal,
      baseCurrency,
      normalizedInvoiceCurrency,
      storeProfile,
      effectiveAt: now,
    );
    final paymentMethodForRounding =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final rawSaleTotalInPaymentCurrency = convertCurrency(
      rawSaleTotalInInvoiceCurrency,
      normalizedInvoiceCurrency,
      normalizedPaymentCurrency,
      storeProfile,
      effectiveAt: now,
    );
    final roundedSaleTotalInPaymentCurrency =
        paymentMethodForRounding.toLowerCase() == 'cash'
            ? normalizeCashAmount(
                rawSaleTotalInPaymentCurrency,
                normalizedPaymentCurrency,
                storeProfile,
              )
            : rawSaleTotalInPaymentCurrency;
    final saleTotalInInvoiceCurrency = convertCurrency(
      roundedSaleTotalInPaymentCurrency,
      normalizedPaymentCurrency,
      normalizedInvoiceCurrency,
      storeProfile,
      effectiveAt: now,
    );
    final saleTotalInBaseCurrency = toBaseCurrencyAmount(
      saleTotalInInvoiceCurrency,
      normalizedInvoiceCurrency,
      storeProfile,
      effectiveAt: now,
    );
    final normalizedCustomerId =
        customerId.trim().isEmpty ? walkInCustomerId : customerId.trim();
    final normalizedCustomerName =
        customerName.trim().isEmpty ? walkInCustomerName : customerName.trim();
    final normalizedPaymentMethod = paymentMethodForRounding;
    final isWalkInSale = normalizedCustomerId == walkInCustomerId ||
        normalizedCustomerName.toLowerCase() ==
            walkInCustomerName.toLowerCase();
    if (isWalkInSale && normalizedPaymentMethod == 'Credit') {
      throw ArgumentError('Walk-in customer sales cannot be credit.');
    }
    final normalizedCashReceived = (cashReceivedAmount ??
            (normalizedPaymentMethod == 'Cash'
                ? saleTotalInInvoiceCurrency
                : 0.0))
        .clamp(0, saleTotalInInvoiceCurrency)
        .toDouble();
    final requestedStatus = paymentStatus.trim().toLowerCase();
    final normalizedPaymentStatus = normalizedPaymentMethod == 'Credit'
        ? (normalizedCashReceived > 0 ? 'partial' : 'credit')
        : (requestedStatus == 'credit'
            ? 'credit'
            : requestedStatus == 'partial'
                ? 'partial'
                : 'paid');
    final normalizedPaidAmount = normalizedPaymentMethod == 'Credit'
        ? normalizedCashReceived
        : saleTotalInInvoiceCurrency;
    if (normalizedPaymentMethod.toLowerCase() == 'cash' &&
        normalizedPaidAmount > 0) {
      final hasOpenDrawer = await AccountingService.hasOpenCashDrawerForDevice(
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
      );
      if (!hasOpenDrawer) {
        throw StateError(
            'لا توجد وردية نقدية مفتوحة لهذا الجهاز. افتح وردية قبل قبول الدفع النقدي.');
      }
    }
    _invoiceCounter += 1;
    final sale = Sale(
      id: 'sale_${_invoiceDevicePrefix}_${_invoiceCounter.toString().padLeft(6, '0')}',
      invoiceNo:
          'INV-$_invoiceDevicePrefix-${_invoiceCounter.toString().padLeft(6, '0')}',
      customerName: normalizedCustomerName,
      customerId: normalizedCustomerId,
      date: now,
      status: 'Paid',
      paymentMethod: normalizedPaymentMethod,
      paymentStatus: normalizedPaymentStatus,
      invoiceCurrency: normalizedInvoiceCurrency,
      paymentCurrency: normalizedPaymentCurrency,
      exchangeRateAtPayment: safePaymentRate,
      baseCurrency: baseCurrency,
      exchangeRateAtInvoice: invoiceRate,
      transactionAmount: saleTotalInInvoiceCurrency,
      baseAmount: saleTotalInBaseCurrency,
      paidBaseAmount: toBaseCurrencyAmount(
        normalizedPaidAmount,
        normalizedInvoiceCurrency,
        storeProfile,
        effectiveAt: now,
      ),
      paidAmount: normalizedPaidAmount,
      cashReceivedAmount: normalizedCashReceived,
      paidAmountInPaymentCurrency: paidAmountInPaymentCurrency ??
          (normalizedPaymentMethod.toLowerCase() == 'cash'
              ? roundedSaleTotalInPaymentCurrency
              : normalizedPaidAmount),
      cashReceivedAmountInPaymentCurrency:
          cashReceivedAmountInPaymentCurrency ??
              (normalizedPaymentMethod.toLowerCase() == 'cash'
                  ? roundedSaleTotalInPaymentCurrency
                  : normalizedCashReceived),
      items: saleItems,
      discount: cleanedDiscount,
      originalDiscount: originalDiscount ?? cleanedDiscount,
      discountCurrency:
          normalizeConfiguredCurrency(discountCurrency, baseCurrency),
      discountExchangeRateAtEntry: discountExchangeRateAtEntry,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );

    _sales.add(sale);
    _recordSyncChange(
      entityType: 'sale',
      entityId: sale.id,
      operation: 'create',
      payload: sale.toJson(),
    );

    for (var lineIndex = 0; lineIndex < saleItems.length; lineIndex += 1) {
      final item = saleItems[lineIndex];
      final index = _productIndexById[item.productId];
      if (index == null) continue;
      var product = _products[index];
      if (!product.trackStock) continue;

      final shortage = item.effectiveBaseQuantity - product.stock;
      if (shortage > 0) {
        final correctedStock = product.stock + shortage;
        product = _withSyncMeta<Product>(
          product.copyWith(stock: correctedStock),
          now,
        );
        _products[index] = product;
        _addStockMovement(
          StockMovement(
            id: '${sale.id}-${item.productId}-auto-correction-$lineIndex',
            productId: item.productId,
            productName: item.productName,
            type: 'auto_correction',
            quantity: shortage,
            date: now,
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            reason: 'Automatic inventory correction before sale',
            adjustmentCategory: 'auto_sale_correction',
            notes:
                'Created automatically because available stock was insufficient during POS sale.',
            unitCost: item.unitCostPerBase,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          recordSync: true,
        );
      }

      final updatedProduct = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - item.effectiveBaseQuantity),
        now,
      );
      _products[index] = updatedProduct;
      _addStockMovement(
        StockMovement(
          id: '${sale.id}-${item.productId}-sale-$lineIndex',
          productId: item.productId,
          productName: item.productName,
          type: 'sale',
          quantity: -item.effectiveBaseQuantity,
          date: now,
          referenceId: sale.id,
          referenceNo: sale.invoiceNo,
          reason: 'Sale invoice',
          unitCost: item.unitCostPerBase,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    _recordSaleLedger(sale, now);
    final productDerivedData = saleItems.any(
      (item) => item.costLayerConsumptions.isNotEmpty,
    );
    await _saveDirty(
      products: true,
      productDerivedData: productDerivedData,
      sales: true,
      stockMovements: true,
      accountTransactions: true,
      invoiceCounter: true,
      sync: true,
    );
    _scheduleSaleAccounting(sale);
    unawaited(
      AppLogger.info(
        area: 'sales',
        action: 'create_invoice',
        message: 'Sale invoice created successfully.',
        details:
            'saleId=${sale.id} invoiceNo=${sale.invoiceNo} total=${sale.invoiceTotal}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'sale',
        entityId: sale.id,
        action: 'create',
        summary: 'Sale invoice created',
        details: jsonEncode(sale.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _activeUser?.fullName ?? _activeUser?.username ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'sales',
        isImportant: true,
      ),
    );
    notifyListeners();
    return sale;
  }

  Future<void> returnSale(String id, {bool restoreStock = true}) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == id);
    final sale = index == -1 ? await _saleByIdFromSqlite(id) : _sales[index];
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) return;

    if (restoreStock) {
      for (final item in sale.items) {
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final now = DateTime.now();
        _restoreInventoryCostLayersFromSaleItem(item, now);
        final updatedProduct = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + item.effectiveBaseQuantity),
          now,
        );
        _products[productIndex] = updatedProduct;
        _addStockMovement(
          StockMovement(
            id: '$id-${item.productId}-sale-return',
            productId: item.productId,
            productName: item.productName,
            type: 'sale_return',
            quantity: item.effectiveBaseQuantity,
            date: now,
            referenceId: id,
            referenceNo: sale.invoiceNo,
            reason: 'Sale returned',
            unitCost: item.unitCostPerBase,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          recordSync: true,
        );
      }
    }

    final now = DateTime.now();
    final returnedSale = _withSyncMeta<Sale>(
      sale.copyWith(
        status: 'Returned',
        paymentStatus: 'returned',
        paidAmount: 0,
        cashReceivedAmount: 0,
        paidAmountInPaymentCurrency: 0,
        cashReceivedAmountInPaymentCurrency: 0,
        paidBaseAmount: 0,
        exchangeDifferenceAmount: 0,
        note: 'Returned on ${now.toIso8601String()}',
      ),
      now,
    );
    if (index != -1) {
      _sales[index] = returnedSale;
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: id,
      operation: 'return',
      payload: returnedSale.toJson(),
    );
    _recordSaleCancelLedger(sale, now, isReturn: true);
    final productDerivedData = restoreStock &&
        sale.items.any((item) => item.costLayerConsumptions.isNotEmpty);
    await _saveDirty(
      products: restoreStock,
      productDerivedData: productDerivedData,
      sales: true,
      stockMovements: restoreStock,
      accountTransactions: true,
      sync: true,
    );
    notifyListeners();
  }

  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == id);
    final sale = index == -1 ? await _saleByIdFromSqlite(id) : _sales[index];
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) return;

    if (restoreStock) {
      for (final item in sale.items) {
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final now = DateTime.now();
        final updatedProduct = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + item.effectiveBaseQuantity),
          now,
        );
        _products[productIndex] = updatedProduct;
        _addStockMovement(
          StockMovement(
            id: '$id-${item.productId}-sale-restore',
            productId: item.productId,
            productName: item.productName,
            type: 'sale_restore',
            quantity: item.effectiveBaseQuantity,
            date: now,
            referenceId: id,
            referenceNo: sale.invoiceNo,
            reason: 'Sale cancelled',
            unitCost: item.unitCostPerBase,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
          recordSync: true,
        );
      }
    }

    final now = DateTime.now();
    final cancelledSale = _withSyncMeta<Sale>(
      sale.copyWith(
        status: status,
        paymentStatus: 'cancelled',
        paidAmount: 0,
        cashReceivedAmount: 0,
        paidAmountInPaymentCurrency: 0,
        cashReceivedAmountInPaymentCurrency: 0,
        paidBaseAmount: 0,
        exchangeDifferenceAmount: 0,
        note: 'Stock restored on ${now.toIso8601String()}',
      ),
      now,
    );
    if (index != -1) {
      _sales[index] = cancelledSale;
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: id,
      operation: 'cancel',
      payload: cancelledSale.toJson(),
    );
    _recordSaleCancelLedger(sale, now);
    await _waitForPendingSaleAccounting(sale.id);
    await AccountingService.reverseEntryForReference(
      referenceType: 'sale',
      referenceId: sale.id,
      reason: 'Sale cancelled',
      createdBy: _deviceId,
    );
    await _saveDirty(
      products: restoreStock,
      productDerivedData: false,
      sales: true,
      stockMovements: restoreStock,
      accountTransactions: true,
      sync: true,
    );
    notifyListeners();
  }

  @Deprecated(
    'Use cancelSale instead. Invoices are cancelled, not physically deleted.',
  )
  Future<void> deleteSale(String id, {bool restoreStock = true}) async {
    // Compatibility wrapper for older call sites. Business flow cancels invoices instead of deleting them.
    await cancelSale(id, status: 'Cancelled', restoreStock: restoreStock);
  }

  double estimateProfit() {
    final grossProfit = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.grossProfit,
    );
    return grossProfit - totalExpensesAmount;
  }

  static const Set<String> _businessBackupBlockedKeys = {
    'deviceId',
    'syncStatus',
    'lastModifiedByDeviceId',
    'syncChanges',
    'syncQueue',
    'cloud_last_pull_cursor',
    'cloudCursor',
    'pairingCode',
    'pairingData',
    'deviceToken',
    'cloudToken',
    'lanSession',
    'hostDeviceId',
    'activeUser',
    'rememberLogin',
    'autoLoginSession',
    'debugLogs',
    'relayState',
    'runtimeCache',
    'pendingSyncOperations',
    'appIdentity',
    'storeEpoch',
    'transportType',
  };

  dynamic _businessBackupValue(dynamic value) {
    if (value is Map) {
      final cleaned = <String, dynamic>{};
      value.forEach((key, item) {
        final textKey = key.toString();
        if (_businessBackupBlockedKeys.contains(textKey)) return;
        cleaned[textKey] = _businessBackupValue(item);
      });
      return cleaned;
    }
    if (value is List) {
      return value.map(_businessBackupValue).toList();
    }
    return value;
  }

  Map<String, dynamic> _businessBackupJson(dynamic item) {
    final raw = item.toJson() as Map<String, dynamic>;
    return Map<String, dynamic>.from(_businessBackupValue(raw) as Map);
  }

  Map<String, dynamic> _backupPayload({
    List<SyncChange>? changes,
    bool includeDeviceAndSyncState = true,
  }) =>
      {
        'version': 12,
        'generatedAt': DateTime.now().toIso8601String(),
        'schemaVersion': 17,
        'backupType': includeDeviceAndSyncState
            ? 'full_device_backup'
            : 'business_backup',
        if (includeDeviceAndSyncState)
          'localDatabaseEntries': LocalDatabaseService.allEntries(),
        if (!includeDeviceAndSyncState) 'storeId': appIdentity.storeId,
        if (!includeDeviceAndSyncState) 'branchId': appIdentity.branchId,
        if (!includeDeviceAndSyncState) 'appVersion': 'stage2',
        if (!includeDeviceAndSyncState) 'platform': appIdentity.platform.name,
        if (!includeDeviceAndSyncState)
          'themeMode':
              LocalDatabaseService.getString(_themeModeKey) ?? 'system',
        'invoiceCounter': _invoiceCounter,
        'purchaseCounter': _purchaseCounter,
        'storeProfile': _storeProfile.toJson(),
        'products': _products
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'customers': _customers
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'sales': _sales
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'saleQuotations': _saleQuotations
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'deliveryNotes': _deliveryNotes
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'billsOfMaterials': _billsOfMaterials
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'manufacturingOrders': _manufacturingOrders
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'suppliers': _suppliers
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'supplierProductPrices': _supplierProductPrices
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'categories': _categories
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'brands': _brands
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'units': _units
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'expenses': _expenses
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'purchases': _purchases
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'stockMovements': _stockMovements
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'inventoryCounts':
            _inventoryCounts.map((item) => item.toJson()).toList(),
        'warehouses': _warehouses
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        'accountTransactions': _accountTransactions
            .map(
              (item) => includeDeviceAndSyncState
                  ? item.toJson()
                  : _businessBackupJson(item),
            )
            .toList(),
        if (includeDeviceAndSyncState) 'deviceId': _deviceId,
        if (includeDeviceAndSyncState)
          'syncChanges':
              (changes ?? _syncChanges).map((item) => item.toJson()).toList(),
        if (includeDeviceAndSyncState)
          'syncQueue': _syncQueue.map((item) => item.toJson()).toList(),
        'roles': _roles.map((item) => item.toJson()).toList(),
        'users': _users.map((item) => item.toJson()).toList(),
        if (includeDeviceAndSyncState) 'appIdentity': appIdentity.toJson(),
        if (includeDeviceAndSyncState) 'storeEpoch': appIdentity.storeEpoch,
        'syncGeneratedAt': DateTime.now().toIso8601String(),
        'syncGeneratedSequence': _syncChanges.isEmpty
            ? 0
            : _syncChanges
                .map((item) => item.sequence)
                .reduce((a, b) => a > b ? a : b),
      };

  Map<String, dynamic> _unifiedSnapshotManifestJson({
    required String jobId,
    required String generatedAt,
    required String kind,
    int totalChunks = 1,
    Iterable<String>? collections,
  }) {
    final identity = appIdentity;
    final sections = collections == null
        ? UnifiedSnapshotCatalog.sections
        : UnifiedSnapshotCatalog.sectionsForCollections(collections);
    return UnifiedSnapshotManifest(
      jobId: jobId,
      generatedAt: generatedAt,
      storeId: identity.storeId,
      branchId: identity.branchId,
      deviceId: _deviceId,
      storeEpoch: identity.storeEpoch.toString(),
      kind: kind,
      totalChunks: totalChunks,
      sections: sections,
    ).toJson();
  }

  void _attachUnifiedSnapshotChunkMetadata(
    List<Map<String, dynamic>> chunks, {
    required String kind,
    required String generatedAt,
  }) {
    final collectionTotals = <String, int>{};
    final collectionSeen = <String, int>{};
    final sectionTotals = <String, int>{};
    final sectionSeen = <String, int>{};
    final sectionIds = <String>{};
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString();
      final section = UnifiedSnapshotCatalog.sectionForCollection(collection);
      chunk['snapshotFormat'] = UnifiedSnapshotManifest.format;
      chunk['snapshotVersion'] = UnifiedSnapshotManifest.version;
      chunk['snapshotKind'] = kind;
      chunk['sectionId'] = section.id;
      chunk['sectionLabelKey'] = section.labelKey;
      chunk['sectionOrder'] = section.order;
      sectionIds.add(section.id);
      collectionTotals[collection] = (collectionTotals[collection] ?? 0) + 1;
      sectionTotals[section.id] = (sectionTotals[section.id] ?? 0) + 1;
    }
    final manifest = _unifiedSnapshotManifestJson(
      jobId: chunks.isEmpty ? '' : (chunks.first['jobId'] ?? '').toString(),
      generatedAt: generatedAt,
      kind: kind,
      totalChunks: chunks.length,
      // Keep the manifest section model stable even when some collections are
      // empty and therefore omitted from the chunk stream.
      collections: null,
    );
    final allCollections = collectionTotals.keys.toList(growable: false);
    final unifiedSections = UnifiedSnapshotCatalog.sections
        .map((section) => section.id)
        .toList(growable: false);
    for (var i = 0; i < chunks.length; i += 1) {
      final collection = (chunks[i]['collection'] ?? '').toString();
      final section = UnifiedSnapshotCatalog.sectionForCollection(collection);
      final collectionIndex = collectionSeen[collection] ?? 0;
      final unifiedSectionIndex = sectionSeen[section.id] ?? 0;
      collectionSeen[collection] = collectionIndex + 1;
      sectionSeen[section.id] = unifiedSectionIndex + 1;
      chunks[i]['totalChunks'] = chunks.length;
      chunks[i]['ordinal'] = i;
      chunks[i]['syncGeneratedAt'] = generatedAt;
      chunks[i]['syncGeneratedSequence'] = _syncChanges.isEmpty
          ? 0
          : _syncChanges
              .map((item) => item.sequence)
              .reduce((a, b) => a > b ? a : b);
      chunks[i]['restoreCommandId'] = currentHostRestoreCommandId();
      chunks[i]['hostRestoreCommandId'] = currentHostRestoreCommandId();
      chunks[i]['rebuildCommandId'] = currentHostRestoreCommandId();
      // Legacy progress fields remain collection-based so the current Cloud
      // provisioning screen and server responses keep working during phase 1.
      chunks[i]['sectionChunkIndex'] = collectionIndex;
      chunks[i]['sectionTotalChunks'] = collectionTotals[collection] ?? 1;
      chunks[i]['allSections'] = allCollections;
      // New unified fields describe the business-level snapshot sections used
      // by both transports in the next phases.
      chunks[i]['unifiedSectionChunkIndex'] = unifiedSectionIndex;
      chunks[i]['unifiedSectionTotalChunks'] = sectionTotals[section.id] ?? 1;
      chunks[i]['allUnifiedSections'] = unifiedSections;
      chunks[i]['snapshotManifest'] = manifest;
    }
  }

  Map<String, List<dynamic>> _unifiedSnapshotCollectionPayloads({
    Set<String>? sectionIds,
  }) {
    final all = <String, List<dynamic>>{
      '_meta': <dynamic>[
        <String, dynamic>{
          'version': 14,
          'generatedAt': DateTime.now().toIso8601String(),
          'schemaVersion': 17,
          'invoiceCounter': _invoiceCounter,
          'purchaseCounter': _purchaseCounter,
          'storeProfile': _storeProfile.toJson(),
          'appIdentity': appIdentity.toJson(),
          'storeEpoch': appIdentity.storeEpoch,
          'syncGeneratedSequence': _syncChanges.isEmpty
              ? 0
              : _syncChanges
                  .map((item) => item.sequence)
                  .reduce((a, b) => a > b ? a : b),
        },
      ],
      'roles': _roles.map((item) => item.toJson()).toList(),
      'users': _users.map((item) => item.toJson()).toList(),
      'categories': _categories.map((item) => item.toJson()).toList(),
      'brands': _brands.map((item) => item.toJson()).toList(),
      'units': _units.map((item) => item.toJson()).toList(),
      'warehouses': _warehouses.map((item) => item.toJson()).toList(),
      'products': _products.map((item) => item.toJson()).toList(),
      'customers': _customers.map((item) => item.toJson()).toList(),
      'suppliers': _suppliers.map((item) => item.toJson()).toList(),
      'supplierProductPrices':
          _supplierProductPrices.map((item) => item.toJson()).toList(),
      'priceLists': _priceLists.map((item) => item.toJson()).toList(),
      'productPrices': _productPrices.map((item) => item.toJson()).toList(),
      'productPriceOverrides':
          _productPriceOverrides.map((item) => item.toJson()).toList(),
      'productCosts': _productCosts.map((item) => item.toJson()).toList(),
      'costingMethodHistory':
          _costingMethodHistory.map((item) => item.toJson()).toList(),
      'inventoryCostingMethod': <dynamic>[_inventoryCostingMethod.code],
      'inventoryCostLayers':
          _inventoryCostLayers.map((item) => item.toJson()).toList(),
      'stockMovements': _stockMovements.map((item) => item.toJson()).toList(),
      'inventoryCounts': _inventoryCounts.map((item) => item.toJson()).toList(),
      'sales': _sales.map((item) => item.toJson()).toList(),
      'saleQuotations': _saleQuotations.map((item) => item.toJson()).toList(),
      'deliveryNotes': _deliveryNotes.map((item) => item.toJson()).toList(),
      'purchases': _purchases.map((item) => item.toJson()).toList(),
      'expenses': _expenses.map((item) => item.toJson()).toList(),
      'accountTransactions':
          _accountTransactions.map((item) => item.toJson()).toList(),
      'billsOfMaterials':
          _billsOfMaterials.map((item) => item.toJson()).toList(),
      'manufacturingOrders':
          _manufacturingOrders.map((item) => item.toJson()).toList(),
    };

    final ordered = <String, List<dynamic>>{};
    for (final section in UnifiedSnapshotCatalog.sections) {
      if (sectionIds != null && !sectionIds.contains(section.id)) continue;
      for (final collection in section.collections) {
        ordered[collection] = all[collection] ?? const <dynamic>[];
      }
    }
    return ordered;
  }

  String _encodeUnifiedSnapshotChunkPayload(Map<String, dynamic> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    final compressed = GZipEncoder().encode(bytes);
    return base64Encode(compressed);
  }

  Map<String, dynamic> _decodeUnifiedSnapshotChunkPayload(
    Map<String, dynamic> chunk,
  ) {
    final encoding = (chunk['encoding'] ?? '').toString();
    final rawPayload = chunk['payload'];
    if (encoding == 'gzip+base64+json' && rawPayload is String) {
      final compressed = base64Decode(rawPayload);
      final bytes = GZipDecoder().decodeBytes(compressed);
      final decoded = jsonDecode(utf8.decode(bytes));
      return Map<String, dynamic>.from(decoded as Map);
    }
    if (rawPayload is Map) return Map<String, dynamic>.from(rawPayload);
    return const <String, dynamic>{};
  }

  /// The single snapshot builder used by Cloud, LAN, restore, repair, and
  /// pairing flows. The same catalog, manifest, payload shape, and chunk
  /// structure are used by both LAN and Cloud transports.
  List<Map<String, dynamic>> exportUnifiedSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) {
    final identity = appIdentity;
    final generatedAt = DateTime.now().toIso8601String();
    final jobId = '${DateTime.now().microsecondsSinceEpoch}-$_deviceId-$kind';
    final collections = _unifiedSnapshotCollectionPayloads(
      sectionIds: sectionIds,
    );

    final chunks = <Map<String, dynamic>>[];
    void addEncodedPayload(
      String collection,
      int index,
      Map<String, dynamic> payload,
      String encoded,
    ) {
      chunks.add({
        'jobId': jobId,
        'storeId': identity.storeId,
        'branchId': identity.branchId,
        'deviceId': _deviceId,
        'collection': collection,
        'chunkIndex': index,
        'encoding': 'gzip+base64+json',
        'payload': encoded,
        'generatedAt': generatedAt,
        'storeEpoch': identity.storeEpoch,
      });
    }

    collections.forEach((collection, list) {
      var chunkIndex = 0;
      if (collection == '_meta') {
        final meta = list.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(list.first as Map);
        addEncodedPayload(
          collection,
          chunkIndex,
          meta,
          _encodeUnifiedSnapshotChunkPayload(meta),
        );
        return;
      }
      if (list.isEmpty) {
        // Empty collections are represented by their absence from the chunk
        // stream. The unified importer already treats missing collections as
        // empty lists, so sending zero-item chunks only wastes requests and can
        // leave large restore publishes waiting on meaningless empty uploads.
        return;
      }

      void addRange(int start, int end) {
        final count = end - start;
        final payload = {'items': list.sublist(start, end)};
        final encoded = _encodeUnifiedSnapshotChunkPayload(payload);
        if (encoded.length <= maxEncodedPayloadBytes || count <= 1) {
          addEncodedPayload(collection, chunkIndex, payload, encoded);
          chunkIndex += 1;
          return;
        }
        final mid = start + (count ~/ 2);
        addRange(start, mid);
        addRange(mid, end);
      }

      for (var start = 0; start < list.length; start += maxItemsPerChunk) {
        final end = min(start + maxItemsPerChunk, list.length);
        addRange(start, end);
      }
    });

    _attachUnifiedSnapshotChunkMetadata(
      chunks,
      kind: kind,
      generatedAt: generatedAt,
    );
    return chunks;
  }

  Map<String, dynamic> unifiedSnapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) {
    final payload = <String, dynamic>{};
    Map<String, dynamic>? manifest;
    var generatedAt = DateTime.now().toIso8601String();
    var generatedSequence = 0;

    for (final chunk in chunks) {
      manifest ??= chunk['snapshotManifest'] is Map
          ? Map<String, dynamic>.from(chunk['snapshotManifest'] as Map)
          : null;
      generatedAt = (chunk['generatedAt'] ?? generatedAt).toString();
      final collection = (chunk['collection'] ?? '').toString();
      if (collection.isEmpty) continue;
      final decoded = _decodeUnifiedSnapshotChunkPayload(chunk);
      if (collection == '_meta') {
        payload.addAll(decoded);
        generatedSequence =
            int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ??
                generatedSequence;
        continue;
      }
      final items = decoded['items'] is List
          ? List<dynamic>.from(decoded['items'] as List)
          : const <dynamic>[];
      final existing = payload[collection];
      if (existing is List) {
        existing.addAll(items);
      } else {
        payload[collection] = List<dynamic>.from(items);
      }
    }

    payload['snapshotManifest'] = manifest ??
        _unifiedSnapshotManifestJson(
          jobId: chunks.isEmpty ? '' : (chunks.first['jobId'] ?? '').toString(),
          generatedAt: generatedAt,
          kind: chunks.isEmpty
              ? 'full_store'
              : (chunks.first['snapshotKind'] ?? 'full_store').toString(),
          totalChunks: chunks.length,
          collections: chunks.map(
            (item) => (item['collection'] ?? '').toString(),
          ),
        );
    payload['syncGeneratedAt'] = generatedAt;
    payload['syncGeneratedSequence'] = generatedSequence;
    return payload;
  }

  List<Map<String, dynamic>> exportCloudLoginBootstrapSnapshotChunks() {
    return exportUnifiedSnapshotChunks(
      kind: 'login_bootstrap',
      sectionIds: {UnifiedSnapshotCatalog.loginSettingsAndUsers.id},
    );
  }

  List<Map<String, dynamic>> exportCloudBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) {
    return exportUnifiedSnapshotChunks(
      kind: 'full_store',
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
  }

  String exportRecoveryFileJson({String cloudApiUrl = ''}) {
    requirePermission(AppPermission.backupExport);
    final payload = <String, dynamic>{
      'format': 'ventio_store_recovery_file',
      'version': 2,
      'generatedAt': DateTime.now().toIso8601String(),
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'cloudApiUrl': cloudApiUrl.trim(),
      'recoveryKey': appIdentity.recoveryKey,
      'storeEpoch': appIdentity.storeEpoch,
    };
    payload['checksum'] = _recoveryChecksum(payload);
    payload['signature'] = _recoverySignature(payload);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, String> parseRecoveryFileJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw ArgumentError('Invalid recovery file.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['format']?.toString() != 'ventio_store_recovery_file') {
      throw ArgumentError('Invalid recovery file format.');
    }
    final version = (payload['version'] as num? ?? 0).toInt();
    if (version < 1 || version > 2) {
      throw ArgumentError('Unsupported recovery file version.');
    }
    final expected = payload['checksum']?.toString() ?? '';
    if (expected.isEmpty || expected != _recoveryChecksum(payload)) {
      throw ArgumentError('Recovery file checksum failed.');
    }
    if (version >= 2) {
      final signature = payload['signature']?.toString() ?? '';
      if (signature.isEmpty || signature != _recoverySignature(payload)) {
        throw ArgumentError('Recovery file signature failed.');
      }
    }
    final storeId = payload['storeId']?.toString().trim().toUpperCase() ?? '';
    final branchId = payload['branchId']?.toString().trim().toUpperCase() ?? '';
    final recoveryKey =
        payload['recoveryKey']?.toString().trim().toUpperCase() ?? '';
    if (!storeId.startsWith('ST-') ||
        branchId.isEmpty ||
        !recoveryKey.startsWith('RK-')) {
      throw ArgumentError(
        'Recovery file is missing required store identity fields.',
      );
    }
    return {
      'storeId': storeId,
      'branchId': branchId,
      'cloudApiUrl': payload['cloudApiUrl']?.toString().trim() ?? '',
      'recoveryKey': recoveryKey,
    };
  }

  String _recoveryChecksum(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    var hash = 2166136261;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String exportBackupJson() {
    requirePermission(AppPermission.backupExport);
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(_backupPayload(includeDeviceAndSyncState: true));
  }

  static const String _hostSnapshotGenerationKey =
      'host_snapshot_generation_v1';
  static const String _hostRestoreCommandIdKey = 'host_restore_command_id_v1';

  String currentHostSnapshotGeneration() {
    if (!appIdentity.isHost) return '';
    final stored = LocalDatabaseService.getString(_hostSnapshotGenerationKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final generation = (payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            payload['restoredAt'] ??
            latest.createdAt.toIso8601String())
        .toString();
    return generation.trim();
  }

  String currentHostRestoreCommandId() {
    if (!appIdentity.isHost) return '';
    final stored = LocalDatabaseService.getString(_hostRestoreCommandIdKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final commandId = (payload['commandId'] ??
            payload['restoreCommandId'] ??
            payload['rebuildCommandId'] ??
            payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            '')
        .toString();
    return commandId.trim();
  }

  Map<String, dynamic> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) {
    final chunks = exportUnifiedSnapshotChunks(
      kind: kind,
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
    final manifest =
        chunks.isNotEmpty && chunks.first['snapshotManifest'] is Map
            ? Map<String, dynamic>.from(chunks.first['snapshotManifest'] as Map)
            : _unifiedSnapshotManifestJson(
                jobId: '',
                generatedAt: DateTime.now().toIso8601String(),
                kind: kind,
                totalChunks: chunks.length,
              );
    final generatedAt = chunks.isEmpty
        ? DateTime.now().toIso8601String()
        : (chunks.first['generatedAt'] ?? DateTime.now().toIso8601String())
            .toString();
    final generatedSequence = _syncChanges.isEmpty
        ? 0
        : _syncChanges
            .map((item) => item.sequence)
            .reduce((a, b) => a > b ? a : b);
    return <String, dynamic>{
      'snapshotFormat': UnifiedSnapshotManifest.format,
      'snapshotVersion': UnifiedSnapshotManifest.version,
      'snapshotKind': kind,
      'snapshotManifest': manifest,
      'snapshotChunks': chunks,
      'totalChunks': chunks.length,
      'syncGeneratedAt': generatedAt,
      'syncGeneratedSequence': generatedSequence,
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
    };
  }

  String exportSyncSnapshotJson() {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(exportUnifiedSnapshotEnvelope(kind: 'full_store'));
  }

  DateTime syncSnapshotGeneratedAtFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return DateTime.tryParse(decoded['syncGeneratedAt']?.toString() ?? '') ??
          DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  int syncSnapshotGeneratedSequenceFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ??
          0;
    } catch (_) {
      return 0;
    }
  }

  String exportSyncChangesJson({DateTime? since, int? sinceSequence}) {
    final sequenceFloor = sinceSequence ?? 0;
    final earliestSequence = _earliestStoredAuthoritativeSequence();
    final latestSequence = _latestStoredAuthoritativeSequence();
    final hasHostRestoreMarker = _syncChanges.any(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'cloud_restore_snapshot_ready',
    );

    // If a client asks for an old sequence that has already been compacted,
    // incremental delivery cannot be trusted. The client must rebuild from a
    // full Host snapshot instead of silently accepting a partial event stream.
    //
    // Restore-specific guard: a manual Host backup restore can replace the
    // local sync log with a fresh, shorter log while existing Clients still
    // remember a higher lastAppliedSequence from the previous dataset. In that
    // case the normal `sequence > sinceSequence` query returns nothing, so the
    // Client never sees the restore marker. Treat `client sequence > latest
    // Host sequence` as a snapshot-required condition whenever a Host restore
    // marker is present.
    final needsSnapshot = sequenceFloor > 0 &&
        ((latestSequence > sequenceFloor &&
                earliestSequence > 0 &&
                sequenceFloor < earliestSequence - 1) ||
            (hasHostRestoreMarker &&
                latestSequence > 0 &&
                sequenceFloor > latestSequence));

    final changes = needsSnapshot
        ? <SyncChange>[]
        : (_syncChanges.where((item) {
            if (sequenceFloor > 0) return item.sequence > sequenceFloor;
            if (since != null) return !item.createdAt.isBefore(since);
            return true;
          }).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence)));
    final cursor = changes.isEmpty
        ? (since ?? DateTime.fromMillisecondsSinceEpoch(0))
        : changes
            .map((item) => item.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final generatedSequence = needsSnapshot
        ? latestSequence
        : (changes.isEmpty
            ? sequenceFloor
            : changes
                .map((item) => item.sequence)
                .reduce((a, b) => a > b ? a : b));
    return jsonEncode({
      'ok': true,
      'deviceId': _deviceId,
      'generatedAt': cursor.toIso8601String(),
      'generatedSequence': generatedSequence,
      'earliestSequence': earliestSequence,
      'latestSequence': latestSequence,
      'requestedSinceSequence': sequenceFloor,
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
      'needsSnapshot': needsSnapshot,
      'changes': changes.map((item) => item.toJson()).toList(),
    });
  }

  String _recoverySignature(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    final storeSecret =
        "${copy['storeId'] ?? ''}|${copy['branchId'] ?? ''}|${copy['recoveryKey'] ?? ''}|${copy['storeEpoch'] ?? ''}";
    return Hmac(
      sha256,
      utf8.encode(storeSecret),
    ).convert(utf8.encode(canonical)).toString();
  }

  List<int> _deriveBackupKey(String password, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(
      pc.Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), 200000, 32),
    );
    return derivator.process(
      Uint8List.fromList(utf8.encode('store_manager_pro|backup_v3|$password')),
    );
  }

  List<int> _deriveBackupKeyV2(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v2|$salt|$password',
    );
    for (var i = 0; i < 100000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  List<int> _aesGcmEncrypt(List<int> plain, List<int> key, List<int> nonce) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(plain));
  }

  List<int> _aesGcmDecrypt(
    List<int> encrypted,
    List<int> key,
    List<int> nonce,
  ) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(encrypted));
  }

  List<int> _deriveBackupKeyV1(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v1|$salt|$password',
    );
    for (var i = 0; i < 25000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  List<int> _xorWithSha256Stream(List<int> input, List<int> key, String nonce) {
    final output = <int>[];
    var counter = 0;
    while (output.length < input.length) {
      final block = sha256.convert([
        ...key,
        ...utf8.encode(nonce),
        ...utf8.encode(counter.toString()),
      ]).bytes;
      for (final byte in block) {
        if (output.length >= input.length) break;
        output.add(input[output.length] ^ byte);
      }
      counter += 1;
    }
    return output;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<void> importBackupJson(String rawJson,
      {Set<String>? selectedSectionIds}) async {
    requirePermission(AppPermission.backupRestore);
    if (appIdentity.isClient) {
      throw StateError('Import Backup is only available on the Host device.');
    }
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    bool wants(String id) =>
        selectedSectionIds == null || selectedSectionIds.contains(id);
    final customImport = selectedSectionIds != null;
    final currentIdentityBeforeImport = appIdentity;
    final preservePairedHostIdentity = currentIdentityBeforeImport.isHost;
    final liveHostConnectionEntries = preservePairedHostIdentity
        ? Map<String, String>.fromEntries(
            LocalDatabaseService.allEntries().entries.where(
                  (entry) => _shouldPreserveLiveHostConnectionKey(entry.key),
                ),
          )
        : const <String, String>{};
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final inventoryCounts = (decoded['inventoryCounts'] as List<dynamic>? ?? [])
        .map(
          (item) => InventoryCountSession.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(
            Map<String, dynamic>.from(decoded['storeProfile'] as Map),
          );

    if (wants('products')) {
      _products
        ..clear()
        ..addAll(products);
    }
    if (wants('customers')) {
      _customers
        ..clear()
        ..addAll(customers);
    }
    if (wants('sales')) {
      _sales
        ..clear()
        ..addAll(sales);
    }
    if (wants('deliveryNotes')) {
      _deliveryNotes
        ..clear()
        ..addAll(deliveryNotes);
    }
    if (wants('manufacturing')) {
      _billsOfMaterials
        ..clear()
        ..addAll(billsOfMaterials);
      _manufacturingOrders
        ..clear()
        ..addAll(manufacturingOrders);
    }
    if (wants('saleQuotations')) {
      _saleQuotations
        ..clear()
        ..addAll(saleQuotations);
    }
    if (wants('suppliers')) {
      _suppliers
        ..clear()
        ..addAll(suppliers);
    }
    if (wants('supplierProductPrices')) {
      _supplierProductPrices
        ..clear()
        ..addAll(supplierProductPrices);
    }
    if (wants('priceLists')) {
      _priceLists
        ..clear()
        ..addAll(priceLists);
    }
    if (wants('productPrices')) {
      _productPrices
        ..clear()
        ..addAll(productPrices);
    }
    if (wants('productPriceOverrides')) {
      _productPriceOverrides
        ..clear()
        ..addAll(productPriceOverrides);
    }
    if (wants('productCosts')) {
      _productCosts
        ..clear()
        ..addAll(productCosts);
      _rebuildProductCostLookupCache();
    }
    if (wants('costingMethodHistory')) {
      _costingMethodHistory
        ..clear()
        ..addAll(costingMethodHistory);
    }
    if (wants('inventoryCostingMethod')) {
      _inventoryCostingMethod = inventoryCostingMethod;
    }
    if (wants('inventoryCostLayers')) {
      _inventoryCostLayers
        ..clear()
        ..addAll(inventoryCostLayers);
      _rebuildInventoryCostLayerLookupCache();
    }
    if (wants('categories')) {
      _categories
        ..clear()
        ..addAll(categories);
    }
    if (wants('brands')) {
      _brands
        ..clear()
        ..addAll(brands);
    }
    if (wants('units')) {
      _units
        ..clear()
        ..addAll(units);
    }
    _ensureCatalogDefaults();
    if (wants('expenses')) {
      _expenses
        ..clear()
        ..addAll(expenses);
    }
    if (wants('purchases')) {
      _purchases
        ..clear()
        ..addAll(purchases);
    }
    if (wants('stockMovements')) {
      _stockMovements
        ..clear()
        ..addAll(stockMovements);
    }
    if (wants('inventoryCounts')) {
      _inventoryCounts
        ..clear()
        ..addAll(inventoryCounts);
    }
    if (wants('warehouses')) {
      _warehouses
        ..clear()
        ..addAll(warehouses);
    }
    _ensureDefaultWarehouse();
    if (wants('accountTransactions')) {
      _accountTransactions
        ..clear()
        ..addAll(accountTransactions);
    }
    _invalidateAccountLedgerCache();
    final restoreFullDeviceBackup =
        decoded['backupType']?.toString() == 'full_device_backup';
    final localDatabaseEntries =
        restoreFullDeviceBackup && decoded['localDatabaseEntries'] is Map
            ? Map<String, dynamic>.from(decoded['localDatabaseEntries'] as Map)
            : const <String, dynamic>{};
    final importedSyncChanges = restoreFullDeviceBackup
        ? (decoded['syncChanges'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) =>
                  SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList()
        : const <SyncChange>[];
    final importedSyncQueue = restoreFullDeviceBackup
        ? (decoded['syncQueue'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) => SyncQueueItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList()
        : const <SyncQueueItem>[];
    if (wants('syncChanges')) {
      _syncChanges
        ..clear()
        ..addAll(
          preservePairedHostIdentity
              ? const <SyncChange>[]
              : importedSyncChanges,
        );
    }
    if (wants('syncQueue')) {
      _syncQueue
        ..clear()
        ..addAll(
          preservePairedHostIdentity
              ? const <SyncQueueItem>[]
              : importedSyncQueue,
        );
    }
    if (wants('deviceId') &&
        restoreFullDeviceBackup &&
        !preservePairedHostIdentity &&
        decoded['deviceId']?.toString().trim().isNotEmpty == true) {
      _deviceId = decoded['deviceId'].toString().trim();
      await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
    }
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    // Business Backup may contain an old Store/Branch identity. When this
    // device is already a paired Host, keep the current sync identity so
    // existing Clients remain attached to the same store after Restore. The
    // restored file replaces business data only; it must not move the Host to a
    // different cloud/LAN store namespace and make Clients miss the rebuild
    // marker.
    if (wants('appIdentity')) {
      final importedStoreId = decoded['storeId']?.toString().trim() ?? '';
      final importedBranchId = decoded['branchId']?.toString().trim() ?? '';
      if (restoreFullDeviceBackup &&
          decoded['appIdentity'] is Map &&
          !preservePairedHostIdentity) {
        _appIdentity = AppIdentity.fromJson(
          Map<String, dynamic>.from(decoded['appIdentity'] as Map),
        );
      } else {
        _appIdentity = currentIdentityBeforeImport.copyWith(
          storeId: preservePairedHostIdentity
              ? currentIdentityBeforeImport.storeId
              : (importedStoreId.isNotEmpty
                  ? importedStoreId.toUpperCase()
                  : currentIdentityBeforeImport.storeId),
          branchId: preservePairedHostIdentity
              ? currentIdentityBeforeImport.branchId
              : (importedBranchId.isNotEmpty
                  ? importedBranchId.toUpperCase()
                  : currentIdentityBeforeImport.branchId),
          deviceId: _deviceId,
          platform: _detectPlatform(),
          updatedAt: DateTime.now(),
        );
      }
    } else {
      _appIdentity = currentIdentityBeforeImport.copyWith(
        deviceId: _deviceId,
        platform: _detectPlatform(),
        updatedAt: DateTime.now(),
      );
    }
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    if (wants('themeMode') && decoded['themeMode'] is String) {
      await LocalDatabaseService.setString(
        _themeModeKey,
        decoded['themeMode'].toString(),
      );
    }
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    }
    if (wants('usersAndRoles')) {
      if (roles.isNotEmpty) {
        _roles
          ..clear()
          ..addAll(roles);
      }
      if (users.isNotEmpty) {
        _replaceUsersWithoutDuplicates(users);
      }
      await _ensureDefaultAdminUser();
    }
    if (wants('counters')) {
      final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
      _invoiceCounter =
          importedCounter > 0 ? importedCounter : _loadInvoiceCounter();
      final importedPurchaseCounter =
          (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
      _purchaseCounter = importedPurchaseCounter > 0
          ? importedPurchaseCounter
          : _loadPurchaseCounter();
    }
    _normalizeCustomers();

    // Full-device backups are expected to restore the whole local database, not
    // only the typed business collections above. Clear the current local store
    // first so stale keys from the previous installation cannot survive, then
    // save the typed collections and finally re-apply the raw exported entries
    // (settings, identity, cursors, login/session flags, feature preferences,
    // and any future keys not represented by AppStore fields yet).
    if (!customImport &&
        restoreFullDeviceBackup &&
        localDatabaseEntries.isNotEmpty) {
      await LocalDatabaseService.clearAll();
    }

    await _saveAll();

    if (wants('localDatabaseEntries') &&
        restoreFullDeviceBackup &&
        localDatabaseEntries.isNotEmpty) {
      // Restore raw exported keys, but keep the current paired Host connection
      // keys. The import remains a full data restore; the live Host/client link
      // is intentionally device-local and must keep using the current tokens,
      // settings, and registries so existing Clients can receive the rebuild
      // command generated below.
      final keysToSkip = <String>{
        _hostSnapshotGenerationKey,
        _hostRestoreCommandIdKey,
        _syncChangesKey,
        _syncQueueKey,
        _syncSequenceKey,
        'cloud_last_pull_cursor',
      };
      for (final entry in localDatabaseEntries.entries) {
        final key = entry.key.toString();
        if (keysToSkip.contains(key)) continue;
        if (preservePairedHostIdentity &&
            _shouldPreserveLiveHostConnectionKey(key)) {
          continue;
        }
        if (preservePairedHostIdentity &&
            _isHostRebuildRuntimeKeyForAnotherImport(key)) {
          continue;
        }
        await LocalDatabaseService.setString(
          key,
          entry.value?.toString() ?? '',
        );
      }
      for (final entry in liveHostConnectionEntries.entries) {
        await LocalDatabaseService.setString(entry.key, entry.value);
      }
      await reloadAllAfterDatabaseChange();
    }

    if (appIdentity.isHost) {
      final restoreGeneration =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final restoreCommandId = 'host_restore_rebuild_$restoreGeneration';
      await LocalDatabaseService.setString(
        _hostSnapshotGenerationKey,
        restoreGeneration,
      );
      await LocalDatabaseService.setString(
        _hostRestoreCommandIdKey,
        restoreCommandId,
      );
      _recordSyncChange(
        entityType: 'system',
        entityId: 'store',
        operation: 'cloud_restore_snapshot_ready',
        payload: {
          'commandId': restoreCommandId,
          'restoreCommandId': restoreCommandId,
          'rebuildCommandId': restoreCommandId,
          'restoredAt': DateTime.now().toIso8601String(),
          'snapshotGeneration': restoreGeneration,
          'restoreGeneration': restoreGeneration,
          'reason': restoreFullDeviceBackup
              ? 'manual_full_device_backup_import'
              : 'manual_backup_import',
          'storeId': appIdentity.storeId,
          'branchId': appIdentity.branchId,
        },
      );
      await _saveSyncStateOnly();
    }

    notifyListeners();
  }

  bool _shouldPreserveLiveHostConnectionKey(String key) {
    return key == _appIdentityKey ||
        key == _deviceIdKey ||
        key == 'lan_sync_settings_v2' ||
        key == 'cloud_api_base_url' ||
        key == 'cloud_auto_sync_enabled' ||
        key == 'cloud_auto_sync_interval_seconds' ||
        key == 'host_authoritative_sync_device_state_v1' ||
        key == 'host_authoritative_sync_peer_states_v1' ||
        key == 'sync_monitoring_suspended_devices_v1' ||
        key == 'sync_monitoring_deleted_devices_v1' ||
        key == 'sync_monitoring_deleted_device_tokens_v1' ||
        key == 'sync_monitoring_wipe_pending_devices_v1' ||
        key == 'sync_monitoring_wipe_pending_device_tokens_v1';
  }

  bool _isHostRebuildRuntimeKeyForAnotherImport(String key) {
    return key.startsWith('applied_host_snapshot_generation_') ||
        key.startsWith('in_progress_host_snapshot_generation_') ||
        key.startsWith('failed_host_snapshot_generation_') ||
        key.startsWith('in_progress_host_snapshot_generation_at_') ||
        key.startsWith('failed_host_snapshot_generation_at_') ||
        key.startsWith('requested_host_snapshot_generation_') ||
        key.startsWith('requested_host_snapshot_generation_at_') ||
        key.startsWith('executed_host_restore_command_') ||
        key.startsWith('in_progress_host_restore_command_');
  }

  int _readVersion(dynamic item) {
    try {
      return item.version as int;
    } catch (_) {
      return 1;
    }
  }

  DateTime _readUpdatedAt(dynamic item) {
    try {
      final updatedAt = item.updatedAt as DateTime;
      return updatedAt;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<AppUser> _dedupeUsersByUsername(List<AppUser> input) {
    final byUsername = <String, AppUser>{};
    for (final user in input) {
      final key = user.username.trim().toLowerCase();
      if (key.isEmpty) continue;
      final current = byUsername[key];
      if (current == null ||
          (user.updatedAt ??
                  user.createdAt ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .isAfter(
            current.updatedAt ??
                current.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        byUsername[key] = user.copyWith(username: key);
      }
    }
    return byUsername.values.toList();
  }

  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) {
    _users
      ..clear()
      ..addAll(_dedupeUsersByUsername(incoming));
    if (_activeUser != null &&
        !_users.any((user) => user.id == _activeUser!.id && user.isActive)) {
      _activeUser = null;
      unawaited(LocalDatabaseService.setString(_activeUserKey, ''));
    }
  }

  void _mergeUsersWithoutUsernameDuplicates(List<AppUser> incoming) {
    final merged = <AppUser>[..._users];
    for (final remote in incoming) {
      final remoteName = remote.username.trim().toLowerCase();
      if (remoteName.isEmpty) continue;
      final sameIdIndex = merged.indexWhere((user) => user.id == remote.id);
      final sameNameIndex = merged.indexWhere(
        (user) => user.username.trim().toLowerCase() == remoteName,
      );
      final index = sameIdIndex != -1 ? sameIdIndex : sameNameIndex;
      final normalizedRemote = remote.copyWith(username: remoteName);
      if (index == -1) {
        merged.add(normalizedRemote);
      } else if ((normalizedRemote.updatedAt ??
              normalizedRemote.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .isAfter(
        merged[index].updatedAt ??
            merged[index].createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0),
      )) {
        merged[index] = normalizedRemote;
      }
    }
    _replaceUsersWithoutDuplicates(merged);
  }

  void _mergeByUpdatedAt<T>(
    List<T> local,
    List<T> incoming,
    String Function(T item) idOf,
  ) {
    for (final remote in incoming) {
      final index = local.indexWhere((item) => idOf(item) == idOf(remote));
      if (index == -1) {
        local.add(remote);
        continue;
      }
      if (_readUpdatedAt(remote).isAfter(_readUpdatedAt(local[index]))) {
        local[index] = remote;
      }
    }
  }

  void _mergeSyncChanges(List<SyncChange> incoming) {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    for (final change in incoming) {
      if (!existingIds.contains(change.id)) {
        _syncChanges.add(change);
        existingIds.add(change.id);
      }
    }
  }

  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    _mergeByUpdatedAt<Product>(_products, products, (item) => item.id);
    _mergeByUpdatedAt<Customer>(_customers, customers, (item) => item.id);
    _mergeByUpdatedAt<Sale>(_sales, sales, (item) => item.id);
    _mergeByUpdatedAt<SaleQuotation>(
      _saleQuotations,
      saleQuotations,
      (item) => item.id,
    );
    _mergeByUpdatedAt<DeliveryNote>(
      _deliveryNotes,
      deliveryNotes,
      (item) => item.id,
    );
    _mergeByUpdatedAt<BillOfMaterials>(
      _billsOfMaterials,
      billsOfMaterials,
      (item) => item.id,
    );
    _mergeByUpdatedAt<ManufacturingOrder>(
      _manufacturingOrders,
      manufacturingOrders,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Supplier>(_suppliers, suppliers, (item) => item.id);
    _mergeByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      supplierProductPrices,
      (item) => item.id,
    );
    _mergeByUpdatedAt<PriceList>(_priceLists, priceLists, (item) => item.id);
    _mergeByUpdatedAt<ProductPrice>(
        _productPrices, productPrices, (item) => item.id);
    _mergeByUpdatedAt<ProductPriceOverride>(
        _productPriceOverrides, productPriceOverrides, (item) => item.id);
    _mergeByUpdatedAt<ProductCost>(
        _productCosts, productCosts, (item) => item.productId);
    _mergeByUpdatedAt<CostingMethodHistory>(
        _costingMethodHistory, costingMethodHistory, (item) => item.id);
    _inventoryCostingMethod = inventoryCostingMethod;
    _mergeByUpdatedAt<InventoryCostLayer>(
        _inventoryCostLayers, inventoryCostLayers, (item) => item.id);
    _rebuildProductCostLookupCache();
    _rebuildInventoryCostLayerLookupCache();
    _mergeByUpdatedAt<CatalogItem>(_categories, categories, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_brands, brands, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_units, units, (item) => item.id);
    _mergeByUpdatedAt<Expense>(_expenses, expenses, (item) => item.id);
    _mergeByUpdatedAt<Purchase>(_purchases, purchases, (item) => item.id);
    _mergeByUpdatedAt<StockMovement>(
      _stockMovements,
      stockMovements,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Warehouse>(_warehouses, warehouses, (item) => item.id);
    _ensureDefaultWarehouse();
    _mergeByUpdatedAt<AccountTransaction>(
      _accountTransactions,
      accountTransactions,
      (item) => item.id,
    );
    _invalidateAccountLedgerCache();
    if (decoded['storeProfile'] != null) {
      _storeProfile = StoreProfile.fromJson(
        Map<String, dynamic>.from(decoded['storeProfile'] as Map),
      );
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    // Never overwrite the local device identity during LAN pull/merge.
    // The remote snapshot belongs to the Host, while this device must keep
    // its own deviceId/deviceName/role so new local changes are queued
    // correctly toward the Host.
    _appIdentity = appIdentity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    );
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    _mergeByUpdatedAt<UserRole>(_roles, roles, (item) => item.id);
    _mergeUsersWithoutUsernameDuplicates(users);
    final nowForMergedRemoteChanges = DateTime.now();
    _mergeSyncChanges(
      markSynced
          ? syncChanges
          : syncChanges.map((change) {
              if (change.deviceId == _deviceId || change.isSynced) {
                return change;
              }
              return change.copyWith(
                isSynced: true,
                syncedAt: nowForMergedRemoteChanges,
              );
            }).toList(),
    );

    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    if (importedCounter > _invoiceCounter) _invoiceCounter = importedCounter;
    final importedPurchaseCounter =
        (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
    if (importedPurchaseCounter > _purchaseCounter) {
      _purchaseCounter = importedPurchaseCounter;
    }

    if (markSynced) {
      final now = DateTime.now();
      for (var i = 0; i < _syncChanges.length; i++) {
        _syncChanges[i] = _syncChanges[i].copyWith(
          isSynced: true,
          syncedAt: now,
        );
      }
    }

    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markAllSyncChangesSynced() async {
    final now = DateTime.now();
    for (var i = 0; i < _syncChanges.length; i++) {
      _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> importSyncSnapshotJson(String rawJson) async {
    if (appIdentity.isHost) {
      throw StateError(
        'Host devices cannot be converted to Clients by importing a sync snapshot.',
      );
    }
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final unifiedChunks = decoded['snapshotChunks'];
    final payload = unifiedChunks is List
        ? unifiedSnapshotPayloadFromChunks(
            unifiedChunks
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
          )
        : decoded;
    await _replaceFromBackupMap(
      payload,
      preserveLocalIdentityForLanClient: true,
    );
  }

  Future<void> _replaceFromBackupMap(
    Map<String, dynamic> decoded, {
    bool preserveLocalIdentityForLanClient = false,
  }) async {
    final unifiedChunks = decoded['snapshotChunks'];
    if (unifiedChunks is List) {
      decoded = unifiedSnapshotPayloadFromChunks(
        unifiedChunks
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
      );
    }
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final inventoryCounts = (decoded['inventoryCounts'] as List<dynamic>? ?? [])
        .map(
          (item) => InventoryCountSession.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(
            Map<String, dynamic>.from(decoded['storeProfile'] as Map),
          );

    if (wants('products')) {
      _products
        ..clear()
        ..addAll(products);
    }
    if (wants('customers')) {
      _customers
        ..clear()
        ..addAll(customers);
    }
    if (wants('sales')) {
      _sales
        ..clear()
        ..addAll(sales);
    }
    if (wants('saleQuotations')) {
      _saleQuotations
        ..clear()
        ..addAll(saleQuotations);
    }
    if (wants('deliveryNotes')) {
      _deliveryNotes
        ..clear()
        ..addAll(deliveryNotes);
    }
    if (wants('manufacturing')) {
      _billsOfMaterials
        ..clear()
        ..addAll(billsOfMaterials);
      _manufacturingOrders
        ..clear()
        ..addAll(manufacturingOrders);
    }
    if (wants('suppliers')) {
      _suppliers
        ..clear()
        ..addAll(suppliers);
    }
    if (wants('supplierProductPrices')) {
      _supplierProductPrices
        ..clear()
        ..addAll(supplierProductPrices);
    }
    if (wants('priceLists')) {
      _priceLists
        ..clear()
        ..addAll(priceLists);
    }
    if (wants('productPrices')) {
      _productPrices
        ..clear()
        ..addAll(productPrices);
    }
    if (wants('productPriceOverrides')) {
      _productPriceOverrides
        ..clear()
        ..addAll(productPriceOverrides);
    }
    if (wants('productCosts')) {
      _productCosts
        ..clear()
        ..addAll(productCosts);
    }
    if (wants('costingMethodHistory')) {
      _costingMethodHistory
        ..clear()
        ..addAll(costingMethodHistory);
    }
    if (wants('inventoryCostingMethod')) {
      _inventoryCostingMethod = inventoryCostingMethod;
    }
    if (wants('inventoryCostLayers')) {
      _inventoryCostLayers
        ..clear()
        ..addAll(inventoryCostLayers);
    }
    if (wants('categories')) {
      _categories
        ..clear()
        ..addAll(categories);
    }
    if (wants('brands')) {
      _brands
        ..clear()
        ..addAll(brands);
    }
    if (wants('units')) {
      _units
        ..clear()
        ..addAll(units);
    }
    if (wants('expenses')) {
      _expenses
        ..clear()
        ..addAll(expenses);
    }
    if (wants('purchases')) {
      _purchases
        ..clear()
        ..addAll(purchases);
    }
    if (wants('stockMovements')) {
      _stockMovements
        ..clear()
        ..addAll(stockMovements);
    }
    if (wants('inventoryCounts')) {
      _inventoryCounts
        ..clear()
        ..addAll(inventoryCounts);
    }
    if (wants('warehouses')) {
      _warehouses
        ..clear()
        ..addAll(warehouses);
    }
    _ensureDefaultWarehouse();
    if (wants('accountTransactions')) {
      _accountTransactions
        ..clear()
        ..addAll(accountTransactions);
    }
    _invalidateAccountLedgerCache();
    _rebuildProductPricingLookupCaches();
    _syncChanges
      ..clear()
      ..addAll(
        preserveLocalIdentityForLanClient
            ? syncChanges.map(
                (item) =>
                    item.copyWith(isSynced: true, syncedAt: DateTime.now()),
              )
            : syncChanges,
      );
    _syncQueue.clear();
    if (!preserveLocalIdentityForLanClient) _syncQueue.addAll(syncQueue);
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    if (preserveLocalIdentityForLanClient) {
      _appIdentity = _identityForLanSnapshotImport(decoded);
      await LocalDatabaseService.setString(
        _appIdentityKey,
        jsonEncode(_appIdentity!.toJson()),
      );
    } else if (decoded['appIdentity'] is Map) {
      _appIdentity = AppIdentity.fromJson(
        Map<String, dynamic>.from(decoded['appIdentity'] as Map),
      ).copyWith(deviceId: _deviceId, platform: _detectPlatform());
      await LocalDatabaseService.setString(
        _appIdentityKey,
        jsonEncode(_appIdentity!.toJson()),
      );
    }
    if (roles.isNotEmpty) {
      _roles
        ..clear()
        ..addAll(roles);
    }
    if (users.isNotEmpty) _replaceUsersWithoutDuplicates(users);
    await _ensureDefaultAdminUser();
    _invoiceCounter =
        (decoded['invoiceCounter'] as num?)?.toInt() ?? _invoiceCounter;
    _purchaseCounter =
        (decoded['purchaseCounter'] as num?)?.toInt() ?? _purchaseCounter;
    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

  Future<int> removeLegacyCloudBootstrapSnapshotQueue() async {
    final identity = appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled) return 0;
    final legacyIds = _syncChanges
        .where(
          (change) =>
              change.entityType == 'system' &&
              change.entityId == 'store' &&
              change.operation == 'restore_snapshot' &&
              change.storeId == identity.storeId &&
              !change.isSynced,
        )
        .map((change) => change.id)
        .toSet();
    if (legacyIds.isEmpty) return 0;
    _syncChanges.removeWhere((change) => legacyIds.contains(change.id));
    _syncQueue.removeWhere((item) => legacyIds.contains(item.changeId));
    await _saveSyncStateOnly();
    notifyListeners();
    return legacyIds.length;
  }

  Future<void> ensureHostCloudBootstrapSnapshotQueued({
    bool force = false,
  }) async {
    // Safety fix: Cloud bootstrap snapshots must not be stored as giant
    // restore_snapshot SyncChange rows. They are now published directly to the
    // Cloud materialized snapshot endpoint in compressed chunks by
    // CloudSyncService._publishBootstrapSnapshotToCloud(). Keep this method as
    // a compatibility no-op so older call-sites no longer bloat the local legacy JSON storage DB.
    final identity = appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled) return;
    final markerKey = 'cloud_host_bootstrap_snapshot_v3_${identity.storeId}';
    await LocalDatabaseService.setString(markerKey, 'direct_chunked');
  }

  /// Diagnostic/safety repair for Host -> Cloud publishing.
  ///
  /// Older builds and aggressive sync-history compaction could leave Host
  /// authoritative SyncChange rows marked unsynced while their cloud queue row
  /// was missing. In that state Host Sync Now reported pendingChanges but had
  /// nothing (or only a small tail) to upload, so Cloud clients stayed behind.
  ///
  /// This method recreates missing cloud queue rows for every unsynced Host
  /// authoritative change before a Host cloud push.
  Future<int> repairMissingHostCloudQueueForPendingChanges() async {
    final identity = appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled) return 0;

    final existingCloudQueueIds = _syncQueue
        .where((item) => item.target == 'cloud' && item.status != 'synced')
        .map((item) => item.changeId)
        .toSet();
    final existingAnyCloudQueueIds = _syncQueue
        .where((item) => item.target == 'cloud')
        .map((item) => item.changeId)
        .toSet();

    var repaired = 0;
    final now = DateTime.now();
    for (final change in _syncChanges) {
      if (change.isSynced) continue;
      if (change.storeId.isNotEmpty && change.storeId != identity.storeId) {
        continue;
      }
      if (change.branchId.isNotEmpty && change.branchId != identity.branchId) {
        continue;
      }
      if (change.deviceId == 'cloud-snapshot') continue;
      // Host only publishes authoritative Host events to Cloud. Client draft
      // commands must first be accepted/restamped by the Host.
      final meta = Map<String, dynamic>.from(
        change.payload['_syncV2'] as Map? ?? const {},
      );
      final kind = (meta['kind'] ?? '').toString();
      final isAuthoritative = kind.isEmpty ||
          kind == 'authoritativeEvent' ||
          change.deviceId == _deviceId;
      if (!isAuthoritative) continue;
      if (existingCloudQueueIds.contains(change.id)) continue;
      if (existingAnyCloudQueueIds.contains(change.id)) {
        // If a cloud queue row exists but is synced while the change is still
        // unsynced, revive it as pending instead of adding a duplicate row.
        for (var i = 0; i < _syncQueue.length; i++) {
          final item = _syncQueue[i];
          if (item.target == 'cloud' &&
              item.changeId == change.id &&
              item.status == 'synced') {
            _syncQueue[i] = item.copyWith(
              status: 'pending',
              updatedAt: now,
              clearNextRetryAt: true,
              lastError: '',
            );
            existingCloudQueueIds.add(change.id);
            repaired += 1;
            break;
          }
        }
        continue;
      }
      _enqueueSyncChangeForTarget(change.id, 'cloud', now);
      existingCloudQueueIds.add(change.id);
      existingAnyCloudQueueIds.add(change.id);
      repaired += 1;
    }

    if (repaired > 0) {
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return repaired;
  }

  bool _shouldMirrorRemoteChangeToCloud(SyncChange change) {
    if (!appIdentity.isCloudEnabled || !appIdentity.isHost) return false;
    if (change.deviceId == _deviceId) return false;
    if (change.deviceId == 'cloud-snapshot') return false;
    if (change.storeId.isNotEmpty && change.storeId != appIdentity.storeId) {
      return false;
    }
    return true;
  }

  Map<String, int> _syncHistoryCompactionResult({
    required int beforeChanges,
    required int beforeQueue,
    required int safeFloorSequence,
    int skipped = 0,
  }) {
    return {
      'removedChanges': beforeChanges - _syncChanges.length,
      'removedQueue': beforeQueue - _syncQueue.length,
      'remainingChanges': _syncChanges.length,
      'remainingQueue': _syncQueue.length,
      'pendingChanges': pendingSyncChanges.length,
      'pendingQueue': pendingSyncQueue.length,
      'safeFloorSequence': safeFloorSequence,
      'earliestSequence': _earliestStoredAuthoritativeSequence(),
      'latestSequence': _latestStoredAuthoritativeSequence(),
      'skipped': skipped,
    };
  }

  String _syncHistoryCompactionLogLine(String label, Map<String, int> result) {
    final pendingQueue = result['pendingQueue'] ?? pendingSyncQueue.length;
    final pendingChanges =
        result['pendingChanges'] ?? pendingSyncChanges.length;
    final remainingQueue = result['remainingQueue'] ?? _syncQueue.length;
    final remainingChanges = result['remainingChanges'] ?? _syncChanges.length;
    final safeFloorSequence = result['safeFloorSequence'] ?? 0;
    final earliestSequence =
        result['earliestSequence'] ?? _earliestStoredAuthoritativeSequence();
    final latestSequence =
        result['latestSequence'] ?? _latestStoredAuthoritativeSequence();
    return '$label role=${appIdentity.deviceRole.name.toUpperCase()} '
        'device=$_deviceId store=${appIdentity.storeId} branch=${appIdentity.branchId} '
        'epoch=${appIdentity.storeEpoch} seq=$_syncSequence '
        'products=${_products.length} customers=${_customers.length} suppliers=${_suppliers.length} '
        'sales=${_sales.length} stockMovements=${_stockMovements.length} '
        'pendingQueue=$pendingQueue pendingChanges=$pendingChanges '
        'allQueue=$remainingQueue allChanges=$remainingChanges '
        'safeFloorSequence=$safeFloorSequence earliestSequence=$earliestSequence latestSequence=$latestSequence';
  }

  /// Cursor-aware sync log compaction.
  ///
  /// Keeps the latest [keepRecentSyncedChanges] synced authoritative changes and
  /// removes older synced queue rows only when they are at/below the active peer
  /// ACK floor. If a Client later asks for a sequence older than the earliest
  /// retained event, [exportSyncChangesJson] returns needsSnapshot=true so the
  /// Client rebuilds from a full Host snapshot instead of applying a partial log.
  Future<Map<String, int>> compactSyncedSyncHistoryForDiagnostics({
    int keepRecentSyncedChanges = _syncMaintenanceKeepRecentChanges,
  }) async {
    return _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: true,
    );
  }

  Future<Map<String, int>> compactSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = _syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact = _syncMaintenanceMinChangesBeforeCompact,
  }) async {
    final safeFloorSequence = _minimumActivePeerAckSequence();
    final before = _syncHistoryCompactionResult(
      beforeChanges: _syncChanges.length,
      beforeQueue: _syncQueue.length,
      safeFloorSequence: safeFloorSequence,
    );

    if (!appIdentity.isHost) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    // Host maintenance must not stop just because there is pending Cloud/LAN work.
    // Pending queue rows are protected inside _compactSyncedSyncHistory via
    // pendingChangeIds, while old already-synced rows can still be trimmed.
    if (safeFloorSequence <= 0) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    if (_syncChanges.length <= minChangesBeforeCompact && _syncQueue.isEmpty) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }

    debugPrint(
      _syncHistoryCompactionLogLine('BEFORE_AUTO_COMPACT_SYNC_HISTORY', before),
    );
    final result = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: true,
      knownSafeFloorSequence: safeFloorSequence,
    );
    debugPrint(
      _syncHistoryCompactionLogLine('AFTER_AUTO_COMPACT_SYNC_HISTORY', result),
    );
    return result;
  }

  /// Client-side sync log compaction. Clients do not own the ACK floor for
  /// other peers, so they compact only their local, already-synced history up
  /// to the latest authoritative sequence they have applied. The Host remains
  /// responsible for serving old events or returning needsSnapshot=true.
  Future<Map<String, int>> compactClientSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = _syncMaintenanceKeepRecentChanges,
  }) async {
    final latestAppliedSequence = _latestStoredAuthoritativeSequence();
    final before = _syncHistoryCompactionResult(
      beforeChanges: _syncChanges.length,
      beforeQueue: _syncQueue.length,
      safeFloorSequence: latestAppliedSequence,
    );

    if (!appIdentity.isClient) {
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    final removedStaleQueue = _removeStaleClientSyncedQueueRows();
    if (removedStaleQueue > 0) {
      debugPrint(
        'CLIENT_SYNC_STALE_QUEUE_CLEANUP removedQueue=$removedStaleQueue '
        'remainingQueue=${_syncQueue.length} pendingQueue=${pendingSyncQueue.length}',
      );
    }
    if (pendingSyncQueue.isNotEmpty || pendingSyncChanges.isNotEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    if (latestAppliedSequence <= 0) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }
    // Client compaction must still run when authoritative history is above the
    // retention window, even if it is below the Host maintenance threshold.
    // Example: Cloud Client can have 353 authoritative synced changes, queue=0,
    // and keepRecentSyncedChanges=200. The old minChangesBeforeCompact=1000
    // guard skipped compaction forever, leaving DB_BLOAT=FAIL although there
    // was no pending work. Skip only when there is nothing to trim.
    final hasAuthoritativeHistoryOverRetention = _syncChanges.any(
          (item) =>
              item.isSynced &&
              item.sequence > 0 &&
              item.sequence <= latestAppliedSequence,
        ) &&
        _syncChanges
                .where((item) => item.isSynced && item.sequence > 0)
                .length >
            keepRecentSyncedChanges;
    final hasSyncedLocalDrafts = _syncChanges.any(
      (item) => item.isSynced && item.sequence <= 0,
    );
    if (!hasAuthoritativeHistoryOverRetention &&
        !hasSyncedLocalDrafts &&
        _syncQueue.isEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ??
              (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }

    debugPrint(
      _syncHistoryCompactionLogLine(
        'BEFORE_CLIENT_AUTO_COMPACT_SYNC_HISTORY',
        before,
      ),
    );
    final rawResult = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: false,
      knownSafeFloorSequence: latestAppliedSequence,
    );
    final result = Map<String, int>.from(rawResult);
    if (removedStaleQueue > 0) {
      result['removedQueue'] =
          (result['removedQueue'] ?? 0) + removedStaleQueue;
      result['remainingQueue'] = _syncQueue.length;
      result['pendingQueue'] = pendingSyncQueue.length;
      result['pendingChanges'] = pendingSyncChanges.length;
    }
    debugPrint(
      _syncHistoryCompactionLogLine(
        'AFTER_CLIENT_AUTO_COMPACT_SYNC_HISTORY',
        result,
      ),
    );
    return result;
  }

  int _removeStaleClientSyncedQueueRows() {
    if (!appIdentity.isClient || _syncQueue.isEmpty || _syncChanges.isEmpty) {
      return 0;
    }
    final changesById = {for (final change in _syncChanges) change.id: change};
    final beforeQueue = _syncQueue.length;
    _syncQueue.removeWhere((item) {
      final change = changesById[item.changeId];
      if (change == null) return false;
      // A Client may keep old draft queue rows as pending/failed after the Host
      // has already accepted the draft and the local SyncChange is marked
      // synced. Those rows are stale bookkeeping, not real pending work. If we
      // leave them in the queue, client compaction is skipped forever and
      // sequence=0 synced draft changes keep bloating the local database.
      return change.isSynced && change.sequence <= 0;
    });
    return beforeQueue - _syncQueue.length;
  }

  Future<Map<String, int>> _compactSyncedSyncHistory({
    required int keepRecentSyncedChanges,
    required bool requireSafeFloorSequence,
    int? knownSafeFloorSequence,
  }) async {
    final beforeChanges = _syncChanges.length;
    final beforeQueue = _syncQueue.length;

    final changesById = {for (final change in _syncChanges) change.id: change};
    final pendingChangeIds = _syncQueue
        .where((item) {
          if (item.status == 'synced') return false;
          final change = changesById[item.changeId];
          // Client-side compaction should not protect stale queue rows tied to
          // local draft changes that are already synced. Those rows may still
          // be marked pending/failed after a network abort, but they no longer
          // represent real pending work.
          if (!requireSafeFloorSequence &&
              change != null &&
              change.isSynced &&
              change.sequence <= 0) {
            return false;
          }
          return true;
        })
        .map((item) => item.changeId)
        .toSet();

    final safeFloorSequence =
        knownSafeFloorSequence ?? _minimumActivePeerAckSequence();
    if (requireSafeFloorSequence && safeFloorSequence <= 0) {
      return _syncHistoryCompactionResult(
        beforeChanges: beforeChanges,
        beforeQueue: beforeQueue,
        safeFloorSequence: safeFloorSequence,
        skipped: 1,
      );
    }

    final isClientLocalCompaction = !requireSafeFloorSequence;

    _syncQueue.removeWhere((item) {
      if (item.status != 'synced') return false;
      // Client-side maintenance may safely remove every already-synced queue
      // row, including local draft commands that never received an
      // authoritative sequence locally (sequence=0). Keeping those rows was the
      // reason Client databases kept thousands of stale SyncQueue entries.
      if (isClientLocalCompaction) return true;

      SyncChange? change;
      for (final candidate in _syncChanges) {
        if (candidate.id == item.changeId) {
          change = candidate;
          break;
        }
      }
      if (change == null) return true;
      if (change.sequence <= 0) return false;
      return change.sequence <= safeFloorSequence;
    });

    final syncedChanges = _syncChanges.where((item) {
      if (!item.isSynced) return false;
      if (pendingChangeIds.contains(item.id)) return false;
      if (item.sequence <= 0) return false;
      return item.sequence <= safeFloorSequence;
    }).toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));
    final keepSyncedIds = syncedChanges
        .take(keepRecentSyncedChanges)
        .map((item) => item.id)
        .toSet();

    _syncChanges.removeWhere((item) {
      if (!item.isSynced) return false;
      if (pendingChangeIds.contains(item.id)) return false;
      // Client-created draft changes commonly remain at sequence=0 after the
      // Host accepts and republishes them as authoritative events. Once they
      // are synced and no pending queue references them, they are stale local
      // bookkeeping and must be removed on Clients.
      if (item.sequence <= 0) return isClientLocalCompaction;
      if (item.sequence > safeFloorSequence) return false;
      return !keepSyncedIds.contains(item.id);
    });

    final result = _syncHistoryCompactionResult(
      beforeChanges: beforeChanges,
      beforeQueue: beforeQueue,
      safeFloorSequence: safeFloorSequence,
    );
    if ((result['removedChanges'] ?? 0) > 0 ||
        (result['removedQueue'] ?? 0) > 0) {
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return result;
  }

  void _enqueueSyncChangeForTarget(
    String changeId,
    String target,
    DateTime now,
  ) {
    if (_syncQueue.any(
      (item) => item.changeId == changeId && item.target == target,
    )) {
      return;
    }
    final item = SyncQueueItem(
      id: '$changeId-$target',
      changeId: changeId,
      target: target,
      status: 'pending',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
    _syncQueue.add(item);
    _sqliteDirtySyncQueue.add(item);
  }

  Future<void> applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToCloud = false,
  }) async {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    final existingEventIds = _syncChanges
        .map((item) => _syncMetaString(item, 'eventId'))
        .where((item) => item.isNotEmpty)
        .toSet();
    final acceptedSourceCommandIds = _syncChanges
        .map((item) => _syncMetaString(item, 'sourceCommandId'))
        .where((item) => item.isNotEmpty)
        .toSet();
    final lastAppliedSequence = SyncDeviceStateStore.load(
      appIdentity,
    ).lastAppliedSequence;
    final currentEpoch = appIdentity.storeEpoch;
    final sorted = [...incoming]..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) {
          return a.sequence.compareTo(b.sequence);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] applyRemote:start incoming=${incoming.length} '
      'sorted=${sorted.length} markApplied=$markAppliedAsSynced '
      'mirrorToCloud=$mirrorToCloud lastAppliedSequence=$lastAppliedSequence '
      'currentEpoch=$currentEpoch',
    );
    for (final change in sorted.take(40)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:item ${SyncDiagnosticsLog.summarizeChange(change)}',
      );
    }
    var changed = false;
    var saveAllBusinessData = false;
    var storeProfileChanged = false;
    var productsChanged = false;
    var customersChanged = false;
    var salesChanged = false;
    var saleQuotationsChanged = false;
    var deliveryNotesChanged = false;
    var billsOfMaterialsChanged = false;
    var manufacturingOrdersChanged = false;
    var suppliersChanged = false;
    var supplierProductPricesChanged = false;
    var categoriesChanged = false;
    var brandsChanged = false;
    var unitsChanged = false;
    var expensesChanged = false;
    var purchasesChanged = false;
    var stockMovementsChanged = false;
    var warehousesChanged = false;
    var accountTransactionsChanged = false;
    var rolesUsersChanged = false;
    var invoiceCounterChanged = false;
    var purchaseCounterChanged = false;

    void markEntityDirty(SyncChange change) {
      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data' ||
              change.operation == 'restore_snapshot') {
            saveAllBusinessData = true;
            rolesUsersChanged = true;
          }
          break;
        case 'store_profile':
          storeProfileChanged = true;
          break;
        case 'app_identity':
          saveAllBusinessData = true;
          break;
        case 'role':
        case 'user':
          rolesUsersChanged = true;
          break;
        case 'product':
          productsChanged = true;
          break;
        case 'customer':
          customersChanged = true;
          break;
        case 'sale':
          salesChanged = true;
          invoiceCounterChanged = true;
          break;
        case 'sale_quotation':
          saleQuotationsChanged = true;
          break;
        case 'delivery_note':
          deliveryNotesChanged = true;
          break;
        case 'bill_of_materials':
          billsOfMaterialsChanged = true;
          break;
        case 'manufacturing_order':
          manufacturingOrdersChanged = true;
          break;
        case 'supplier':
          suppliersChanged = true;
          break;
        case 'supplier_product_price':
          supplierProductPricesChanged = true;
          break;
        case 'category':
          categoriesChanged = true;
          break;
        case 'brand':
          brandsChanged = true;
          break;
        case 'unit':
          unitsChanged = true;
          break;
        case 'expense':
          expensesChanged = true;
          break;
        case 'purchase':
          purchasesChanged = true;
          purchaseCounterChanged = true;
          break;
        case 'stock_movement':
          stockMovementsChanged = true;
          productsChanged = true;
          break;
        case 'warehouse':
          warehousesChanged = true;
          break;
        case 'account_transaction':
          accountTransactionsChanged = true;
          break;
      }
    }

    for (final change in sorted) {
      if (_isReplayOrDuplicateSyncEvent(
        change,
        existingEnvelopeIds: existingIds,
        existingEventIds: existingEventIds,
        acceptedSourceCommandIds: acceptedSourceCommandIds,
        lastAppliedSequence: lastAppliedSequence,
      )) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipDuplicate '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'lastAppliedSequence=$lastAppliedSequence',
        );
        continue;
      }
      final incomingEpoch = change.storeEpoch;
      if (incomingEpoch < currentEpoch &&
          !(change.entityType == 'system' &&
              change.operation == 'reset_store_data')) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipEpoch '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'incomingEpoch=$incomingEpoch currentEpoch=$currentEpoch',
        );
        continue;
      }
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:before '
        '${SyncDiagnosticsLog.summarizeChange(change)} '
        'localDevice=$_deviceId countBeforeCustomers=${_customers.length} '
        'existsBefore=${_customers.any((item) => item.id == change.entityId)}',
      );
      await _applySyncChangePayload(change);
      if (change.entityType == 'customer') {
        final storedIndex =
            _customers.indexWhere((item) => item.id == change.entityId);
        final stored = storedIndex == -1 ? null : _customers[storedIndex];
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:after entity=customer '
          'id=${change.entityId} name=${stored?.name} '
          'deletedAt=${stored?.deletedAt?.toIso8601String()} '
          'syncStatus=${stored?.syncStatus} version=${stored?.version} '
          'countAfter=${_customers.length}',
        );
      }
      _rememberRemoteSqliteBusinessRows(change);
      markEntityDirty(change);
      final shouldMirrorToCloud =
          mirrorToCloud && _shouldMirrorRemoteChangeToCloud(change);

      // Host-authority sync note:
      // Any draft accepted by the Host must become a new authoritative Host
      // event, even in LAN-only mode. v12 only restamped events that were also
      // mirrored to Cloud; pure Local/LAN installs kept the original Client
      // timestamp, so other Clients could miss the delta behind their cursor.
      // Restamping on every Host acceptance makes Local sync timing stable.
      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority =
          appIdentity.isHost && change.deviceId != _deviceId;
      final incomingMeta = _syncV2MetaOf(change);
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? _newSyncEnvelopeId(acceptedAt, 'evt')
          : (_syncMetaString(change, 'eventId').isNotEmpty
              ? _syncMetaString(change, 'eventId')
              : change.id);
      final authoritativePayload = shouldRestampAsHostAuthority
          ? <String, dynamic>{
              ...change.payload,
              '_syncV2': <String, dynamic>{
                ...incomingMeta,
                'kind': 'authoritativeEvent',
                'requestId': requestId,
                'eventId': authoritativeEventId,
                'acceptedByHostDeviceId': _deviceId,
                'acceptedAt': acceptedAt.toIso8601String(),
                'sourceCommandId': change.id,
                'sourceCommandDeviceId': change.deviceId,
              },
            }
          : change.payload;
      final authoritativeChange = shouldRestampAsHostAuthority
          ? change.copyWith(
              id: authoritativeEventId,
              createdAt: acceptedAt,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              payload: authoritativePayload,
              storeEpoch: appIdentity.storeEpoch,
              sequence: _nextSyncSequence(),
            )
          : change;
      final storedChange = markAppliedAsSynced && !shouldMirrorToCloud
          ? authoritativeChange.copyWith(isSynced: true, syncedAt: acceptedAt)
          : authoritativeChange.copyWith(isSynced: false, syncedAt: null);
      _syncChanges.add(storedChange);
      _sqliteDirtySyncChanges.add(storedChange);
      if (shouldMirrorToCloud) {
        _enqueueSyncChangeForTarget(storedChange.id, 'cloud', acceptedAt);
      }
      existingIds.add(change.id);
      existingIds.add(storedChange.id);
      final storedEventId = _syncMetaString(storedChange, 'eventId');
      if (storedEventId.isNotEmpty) existingEventIds.add(storedEventId);
      final storedSourceCommandId = _syncMetaString(
        storedChange,
        'sourceCommandId',
      );
      if (storedSourceCommandId.isNotEmpty) {
        acceptedSourceCommandIds.add(storedSourceCommandId);
      }
      changed = true;
    }
    if (changed) {
      _ensureCatalogDefaults();
      _normalizeCustomers();
      if (saveAllBusinessData) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyRemote:saveAll customersChanged=$customersChanged');
        await _saveAll();
      } else {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:saveDirty customersChanged=$customersChanged '
          'productsChanged=$productsChanged sync=true',
        );
        await Future.wait([
          if (rolesUsersChanged) _saveRolesAndUsers(),
          _saveDirty(
            products: productsChanged,
            customers: customersChanged,
            sales: salesChanged,
            saleQuotations: saleQuotationsChanged,
            deliveryNotes: deliveryNotesChanged,
            billsOfMaterials: billsOfMaterialsChanged,
            manufacturingOrders: manufacturingOrdersChanged,
            suppliers: suppliersChanged,
            supplierProductPrices: supplierProductPricesChanged,
            expenses: expensesChanged,
            purchases: purchasesChanged,
            stockMovements: stockMovementsChanged,
            warehouses: warehousesChanged,
            accountTransactions: accountTransactionsChanged,
            storeProfile: storeProfileChanged,
            categories: categoriesChanged,
            brands: brandsChanged,
            units: unitsChanged,
            invoiceCounter: invoiceCounterChanged,
            purchaseCounter: purchaseCounterChanged,
            sync: true,
          ),
        ]);
      }
      _touchDataRevisions(
        products: productsChanged,
        customers: customersChanged,
        sales: salesChanged,
        deliveryNotes: deliveryNotesChanged,
        storeProfile: storeProfileChanged,
      );
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:notify changed=true customers=${_customers.length} '
        'visibleCustomers=${customers.length} '
        'customerNames=${customers.map((item) => item.name).join(',')}',
      );
      notifyListeners();
    } else {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:done changed=false customers=${_customers.length} '
        'visibleCustomers=${customers.length}',
      );
    }
  }

  String _conflictKey(String value) => value.trim().toLowerCase();

  void _addDuplicateConflicts<T>(
    List<DataConflict> output,
    Iterable<T> items,
    String entityType,
    String keyName,
    String Function(T item) keyOf,
    String Function(T item) idOf, {
    bool blocking = false,
    String message = '',
  }) {
    final groups = <String, List<T>>{};
    final display = <String, String>{};
    for (final item in items) {
      final raw = keyOf(item).trim();
      final key = _conflictKey(raw);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => <T>[]).add(item);
      display.putIfAbsent(key, () => raw);
    }
    groups.forEach((key, grouped) {
      final ids = grouped
          .map(idOf)
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
      if (ids.length > 1) {
        output.add(
          DataConflict(
            entityType: entityType,
            keyName: keyName,
            keyValue: display[key] ?? key,
            recordIds: ids,
            blocking: blocking,
            message: message,
          ),
        );
      }
    });
  }

  List<DataConflict> _detectDataConflicts() {
    final result = <DataConflict>[];
    _addDuplicateConflicts<Customer>(
      result,
      _customers.where(
        (item) => !item.isDeleted && item.id != walkInCustomerId,
      ),
      'Customers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Created offline on more than one device. Keep both records and review manually.',
    );
    _addDuplicateConflicts<Supplier>(
      result,
      _suppliers.where((item) => !item.isDeleted),
      'Suppliers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Supplier names are duplicated after sync. Review manually; records were not merged.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where((item) => !item.isDeleted),
      'Products',
      'code',
      (item) => item.code,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate product codes can affect search, sales, stock, and reports.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where(
        (item) => !item.isDeleted && item.barcode.trim().isNotEmpty,
      ),
      'Products',
      'barcode',
      (item) => item.barcode,
      (item) => item.id,
      blocking: true,
      message:
          'Barcode is ambiguous. Avoid barcode sales until one product barcode is changed.',
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<AppUser>(
      result,
      _users,
      'Users',
      'username',
      (item) => item.username,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate usernames are a security conflict. Rename or disable one user before relying on login.',
    );
    _addDuplicateConflicts<UserRole>(
      result,
      _roles,
      'Roles',
      'name',
      (item) => item.name,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate role names can confuse permissions. Rename one role.',
    );
    _addDuplicateConflicts<SupplierProductPrice>(
      result,
      _supplierProductPrices.where((item) => !item.isDeleted),
      'Supplier Product Prices',
      'product + supplier',
      (item) => '${item.productId} / ${item.supplierId}',
      (item) => item.id,
      blocking: true,
      message:
          'A product should have only one active price per supplier. Merge or delete the duplicate record.',
    );
    _addDuplicateConflicts<Sale>(
      result,
      _sales.where((item) => !item.isDeleted),
      'Sales',
      'invoice number',
      (item) => item.invoiceNo,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate invoice numbers must be reviewed before printing/exporting final reports.',
    );
    return result;
  }

  bool _remoteWins(dynamic incoming, dynamic local) {
    final incomingVersion = _readVersion(incoming);
    final localVersion = _readVersion(local);
    if (incomingVersion != localVersion) return incomingVersion > localVersion;

    final incomingUpdatedAt = _readUpdatedAt(incoming);
    final localUpdatedAt = _readUpdatedAt(local);
    if (incomingUpdatedAt.isAfter(localUpdatedAt)) return true;
    if (incomingUpdatedAt.isBefore(localUpdatedAt)) return false;

    // Deterministic tie-breaker for same-version/same-time writes. This avoids
    // oscillation between devices while keeping the Host-authoritative event
    // stream stable.
    try {
      final incomingDevice = (incoming.lastModifiedByDeviceId as String?) ??
          (incoming.deviceId as String?) ??
          '';
      final localDevice = (local.lastModifiedByDeviceId as String?) ??
          (local.deviceId as String?) ??
          '';
      return incomingDevice.compareTo(localDevice) >= 0;
    } catch (_) {
      return true;
    }
  }

  void _upsertByUpdatedAt<T>(
    List<T> list,
    T incoming,
    String Function(T item) idOf,
  ) {
    final index = list.indexWhere((item) => idOf(item) == idOf(incoming));
    if (index == -1) {
      list.add(incoming);
    } else if (_remoteWins(incoming, list[index])) {
      list[index] = incoming;
    }
  }

  void _applySupplierProductPriceFromSync(SupplierProductPrice incoming) {
    final normalized = incoming.copyWith(syncStatus: 'synced');
    if (!normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (item.isDeleted || item.id == normalized.id) continue;
        final sameProductSupplier = item.productId == normalized.productId &&
            item.supplierId == normalized.supplierId;
        if (!sameProductSupplier) continue;
        if (_remoteWins(normalized, item)) {
          _supplierProductPrices[i] = item.copyWith(
            deletedAt: normalized.updatedAt,
            updatedAt: normalized.updatedAt,
            syncStatus: 'synced',
            notes: [
              item.notes,
              'Merged duplicate supplier price from sync',
            ].where((part) => part.trim().isNotEmpty).join(' — '),
          );
        } else {
          return;
        }
      }
    }
    if (normalized.isPreferred && !normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted &&
            item.productId == normalized.productId &&
            item.id != normalized.id &&
            item.isPreferred) {
          _supplierProductPrices[i] = item.copyWith(
            isPreferred: false,
            updatedAt: normalized.updatedAt.isAfter(item.updatedAt)
                ? normalized.updatedAt
                : item.updatedAt,
            syncStatus: 'synced',
          );
        }
      }
    }
    _upsertByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      normalized,
      (item) => item.id,
    );
  }

  Future<void> _applySyncChangePayload(SyncChange change) async {
    final p = change.payload;
    switch (change.entityType) {
      case 'system':
        if (change.operation == 'reset_store_data') {
          _syncChanges.clear();
          _syncQueue.clear();
          final nextEpoch = change.storeEpoch > appIdentity.storeEpoch
              ? change.storeEpoch
              : appIdentity.storeEpoch + 1;
          _appIdentity = appIdentity.copyWith(
            storeEpoch: nextEpoch,
            updatedAt: DateTime.now(),
          );
          await LocalDatabaseService.setString(
            _appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
          _resetBusinessDataInMemory(
            keepStoreProfile: p['keepStoreProfile'] as bool? ?? true,
          );
        } else if (change.operation == 'restore_snapshot') {
          // A cloud/LAN bootstrap snapshot contains the Host identity. Never let
          // a Client import that identity or it may start behaving as the Host.
          await _replaceFromBackupMap(
            p,
            preserveLocalIdentityForLanClient: true,
          );
        } else if (change.operation == 'request_snapshot') {
          // Cloud Clients cannot contact the Host directly. They place a
          // request in the Cloud relay; when the Host sees it, it immediately
          // queues a fresh full restore_snapshot event for the authoritative
          // Cloud stream. This makes Cloud Rebuild generate a fresh Host
          // snapshot instead of relying only on whatever snapshot already
          // exists in entity_snapshots.
          if (appIdentity.isHost && appIdentity.isCloudEnabled) {
            // Cloud snapshots are served from entity_snapshots through the
            // chunked bootstrap publisher, not queued as giant SyncChange rows.
            await ensureHostCloudBootstrapSnapshotQueued();
          }
        }
        break;
      case 'host_transfer':
        if (change.operation == 'request') {
          // Keep the latest transfer request visible to the current Host UI.
          if (appIdentity.isHost) {
            await LocalDatabaseService.setString(
              _hostTransferRequestKey,
              jsonEncode(p),
            );
          }
        } else if (change.operation == 'approve') {
          final approvedDeviceId =
              p['approvedDeviceId']?.toString().trim() ?? '';
          if (approvedDeviceId == _deviceId) {
            await LocalDatabaseService.setString(
              _hostTransferApprovedDeviceKey,
              approvedDeviceId,
            );
          }
        } else if (change.operation == 'new_host_activated' ||
            change.operation == 'HOST_CHANGED' ||
            change.operation == 'notify_clients_host_changed') {
          final newHostDeviceId = p['newHostDeviceId']?.toString().trim() ?? '';
          final oldHostDeviceId = p['oldHostDeviceId']?.toString().trim() ?? '';
          final shouldSwitchToNewHost = newHostDeviceId.isNotEmpty &&
              newHostDeviceId != _deviceId &&
              (appIdentity.isClient ||
                  (appIdentity.isHost && oldHostDeviceId == _deviceId));
          if (shouldSwitchToNewHost) {
            await _forceApplyRoleFromTransfer(
              appIdentity.copyWith(
                deviceRole: DeviceRole.client,
                hostDeviceId: newHostDeviceId,
                updatedAt: DateTime.now(),
              ),
            );
            await _storeHostTransferNotification({
              'type': 'host_changed',
              'newHostDeviceId': newHostDeviceId,
              'oldHostDeviceId': oldHostDeviceId,
              'storeId': p['storeId']?.toString() ?? appIdentity.storeId,
              'branchId': p['branchId']?.toString() ?? appIdentity.branchId,
              'receivedAt': DateTime.now().toIso8601String(),
            });
          }
        }
        break;
      case 'store_profile':
        _storeProfile = StoreProfile.fromJson(p);
        AccountingService.configureMoneyPolicy(_storeProfile);
        break;
      case 'app_identity':
        if (change.entityId == _deviceId) {
          final incomingIdentity = _normalizedLocalIdentity(
            AppIdentity.fromJson(p),
          );
          _assertSafeRoleTransition(
            incomingIdentity,
            source: 'remote app identity change',
          );
          _appIdentity = incomingIdentity;
          await LocalDatabaseService.setString(
            _appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
        }
        break;
      case 'role':
        if (change.operation == 'delete') {
          _roles.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
        } else {
          _upsertByUpdatedAt<UserRole>(
            _roles,
            UserRole.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'user':
        if (change.operation == 'delete') {
          _users.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
          if (_activeUser?.id == change.entityId) _activeUser = null;
        } else {
          final incoming = AppUser.fromJson(p);
          _upsertByUpdatedAt<AppUser>(_users, incoming, (item) => item.id);
          if (_activeUser?.id == incoming.id) _activeUser = incoming;
        }
        break;
      case 'product':
        if (change.operation == 'delete' && p.isEmpty) {
          _products.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Product>(
            _products,
            Product.fromJson(p),
            (item) => item.id,
          );
        }
        _rebuildProductIndexes();
        break;
      case 'customer':
        if (change.operation == 'delete' && p.isEmpty) {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer deleteEmpty id=${change.entityId} '
            'before=${_customers.length}',
          );
          _customers.removeWhere((item) => item.id == change.entityId);
        } else {
          final incoming = Customer.fromJson(p);
          final beforeIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final before = beforeIndex == -1 ? null : _customers[beforeIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer upsert id=${incoming.id} '
            'name=${incoming.name} op=${change.operation} seq=${change.sequence} '
            'incomingUpdatedAt=${incoming.updatedAt.toIso8601String()} '
            'incomingDeletedAt=${incoming.deletedAt?.toIso8601String()} '
            'incomingStatus=${incoming.syncStatus} incomingVersion=${incoming.version} '
            'beforeExists=${before != null} '
            'beforeUpdatedAt=${before?.updatedAt.toIso8601String()} '
            'beforeDeletedAt=${before?.deletedAt?.toIso8601String()} '
            'beforeStatus=${before?.syncStatus} beforeVersion=${before?.version}',
          );
          _upsertByUpdatedAt<Customer>(
            _customers,
            incoming,
            (item) => item.id,
          );
          final afterIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final after = afterIndex == -1 ? null : _customers[afterIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer result id=${incoming.id} '
            'afterExists=${after != null} afterName=${after?.name} '
            'afterUpdatedAt=${after?.updatedAt.toIso8601String()} '
            'afterDeletedAt=${after?.deletedAt?.toIso8601String()} '
            'afterStatus=${after?.syncStatus} afterVersion=${after?.version} '
            'total=${_customers.length}',
          );
        }
        _rebuildCustomerIndexes();
        break;
      case 'supplier':
        if (change.operation == 'delete' && p.isEmpty) {
          _suppliers.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Supplier>(
            _suppliers,
            Supplier.fromJson(p),
            (item) => item.id,
          );
        }
        _rebuildSupplierIndexes();
        break;
      case 'supplier_product_price':
        if (change.operation == 'delete' && p.isEmpty) {
          _supplierProductPrices.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _applySupplierProductPriceFromSync(SupplierProductPrice.fromJson(p));
        }
        break;
      case 'expense':
        if (change.operation == 'delete' && p.isEmpty) {
          final expenseIndex = _expenseIndexForId(change.entityId);
          if (expenseIndex != -1) {
            _removeExpenseAtIndex(expenseIndex);
            _touchExpensesData();
          }
        } else {
          final incoming = Expense.fromJson(p);
          _upsertByUpdatedAt<Expense>(
            _expenses,
            incoming,
            (item) => item.id,
          );
          _rebuildExpenseIndexes();
          _touchExpensesData();
        }
        break;
      case 'category':
        if (change.operation == 'delete' && p.isEmpty) {
          _categories.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _categories,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'brand':
        if (change.operation == 'delete' && p.isEmpty) {
          _brands.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _brands,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'unit':
        if (change.operation == 'delete' && p.isEmpty) {
          _units.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _units,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'sale':
        if (change.operation == 'delete' && p.isEmpty) {
          _sales.removeWhere((item) => item.id == change.entityId);
        } else {
          final incomingSale = Sale.fromJson(p);
          _upsertByUpdatedAt<Sale>(_sales, incomingSale, (item) => item.id);
          final invoiceNumber = _invoiceSequenceFromNo(incomingSale.invoiceNo);
          if (invoiceNumber > _invoiceCounter) _invoiceCounter = invoiceNumber;
        }
        break;
      case 'sale_quotation':
        if (change.operation == 'delete' && p.isEmpty) {
          _saleQuotations.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<SaleQuotation>(
            _saleQuotations,
            SaleQuotation.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'delivery_note':
        if (change.operation == 'delete' && p.isEmpty) {
          _deliveryNotes.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<DeliveryNote>(
            _deliveryNotes,
            DeliveryNote.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'bill_of_materials':
        if (change.operation == 'delete' && p.isEmpty) {
          _billsOfMaterials.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<BillOfMaterials>(
            _billsOfMaterials,
            BillOfMaterials.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'manufacturing_order':
        if (change.operation == 'delete' && p.isEmpty) {
          _manufacturingOrders.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _upsertByUpdatedAt<ManufacturingOrder>(
            _manufacturingOrders,
            ManufacturingOrder.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'purchase':
        if (change.operation == 'delete' && p.isEmpty) {
          final purchaseIndex = _purchaseIndexForId(change.entityId);
          if (purchaseIndex != -1) {
            _removePurchaseAtIndex(purchaseIndex);
            _touchPurchasesData();
          }
        } else {
          final incomingPurchase = Purchase.fromJson(p);
          _upsertByUpdatedAt<Purchase>(
            _purchases,
            incomingPurchase,
            (item) => item.id,
          );
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
        }
        break;
      case 'account_transaction':
        if (change.operation == 'delete' && p.isEmpty) {
          final transactionIndex =
              _accountTransactionIndexForId(change.entityId);
          if (transactionIndex != -1) {
            final previous = _accountTransactions[transactionIndex];
            _removeAccountTransactionAtIndex(transactionIndex);
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: previous.copyWith(deletedAt: DateTime.now()),
            );
          }
          _invalidateAccountLedgerCache();
        } else {
          final incoming = AccountTransaction.fromJson(p);
          final previousIndex = _accountTransactionIndexForId(incoming.id);
          final previous =
              previousIndex == -1 ? null : _accountTransactions[previousIndex];
          _upsertByUpdatedAt<AccountTransaction>(
            _accountTransactions,
            incoming,
            (item) => item.id,
          );
          final currentIndex = _accountTransactionIndexForId(incoming.id);
          final current =
              currentIndex == -1 ? null : _accountTransactions[currentIndex];
          if (current != null) {
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: current,
            );
          }
          _rebuildAccountTransactionIndexes();
          _invalidateAccountLedgerCache();
        }
        break;
      case 'stock_movement':
        final movement = StockMovement.fromJson(p);
        if (_stockMovementIndexForId(movement.id) != -1) break;
        _putStockMovementAtIndex(
          movement.copyWith(syncStatus: 'synced'),
          _stockMovements.length,
        );
        final productId = movement.productId;
        final quantity = movement.quantity;
        final index = _productIndexById[productId];
        if (index != null && quantity != 0) {
          final product = _products[index];
          if (!product.trackStock) break;
          final at = movement.date;
          _products[index] = product.copyWith(
            stock: product.stock + quantity,
            cost: movement.type == 'purchase_receive' && movement.unitCost > 0
                ? movement.unitCost
                : product.cost,
            usdCost:
                movement.type == 'purchase_receive' && movement.unitCost > 0
                    ? movement.unitCost
                    : product.usdCost,
            updatedAt: at.isAfter(product.updatedAt) ? at : product.updatedAt,
            syncStatus: 'synced',
          );
        }
        break;
    }
  }

  String? _remoteSyncChangeApplyProblem(SyncChange change) {
    if (change.entityType == 'system') return null;

    bool exists<T>(Iterable<T> items, String Function(T item) idOf) =>
        items.any((item) => idOf(item) == change.entityId);
    final deleteWithEmptyPayload =
        change.operation == 'delete' && change.payload.isEmpty;

    switch (change.entityType) {
      case 'store_profile':
        return null;
      case 'app_identity':
        return null;
      case 'role':
        return deleteWithEmptyPayload ||
                exists<UserRole>(_roles, (item) => item.id)
            ? null
            : 'role ${change.entityId} was not stored locally';
      case 'user':
        return deleteWithEmptyPayload ||
                exists<AppUser>(_users, (item) => item.id)
            ? null
            : 'user ${change.entityId} was not stored locally';
      case 'product':
        return deleteWithEmptyPayload ||
                exists<Product>(_products, (item) => item.id)
            ? null
            : 'product ${change.entityId} was not stored locally';
      case 'customer':
        return deleteWithEmptyPayload ||
                exists<Customer>(_customers, (item) => item.id)
            ? null
            : 'customer ${change.entityId} was not stored locally';
      case 'supplier':
        return deleteWithEmptyPayload ||
                exists<Supplier>(_suppliers, (item) => item.id)
            ? null
            : 'supplier ${change.entityId} was not stored locally';
      case 'supplier_product_price':
        return deleteWithEmptyPayload ||
                exists<SupplierProductPrice>(
                  _supplierProductPrices,
                  (item) => item.id,
                )
            ? null
            : 'supplier product price ${change.entityId} was not stored locally';
      case 'expense':
        return deleteWithEmptyPayload ||
                exists<Expense>(_expenses, (item) => item.id)
            ? null
            : 'expense ${change.entityId} was not stored locally';
      case 'category':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_categories, (item) => item.id)
            ? null
            : 'category ${change.entityId} was not stored locally';
      case 'brand':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_brands, (item) => item.id)
            ? null
            : 'brand ${change.entityId} was not stored locally';
      case 'unit':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_units, (item) => item.id)
            ? null
            : 'unit ${change.entityId} was not stored locally';
      case 'sale':
        return deleteWithEmptyPayload || exists<Sale>(_sales, (item) => item.id)
            ? null
            : 'sale ${change.entityId} was not stored locally';
      case 'sale_quotation':
        return deleteWithEmptyPayload ||
                exists<SaleQuotation>(_saleQuotations, (item) => item.id)
            ? null
            : 'sale quotation ${change.entityId} was not stored locally';
      case 'delivery_note':
        return deleteWithEmptyPayload ||
                exists<DeliveryNote>(_deliveryNotes, (item) => item.id)
            ? null
            : 'delivery note ${change.entityId} was not stored locally';
      case 'bill_of_materials':
        return deleteWithEmptyPayload ||
                exists<BillOfMaterials>(_billsOfMaterials, (item) => item.id)
            ? null
            : 'BOM ${change.entityId} was not stored locally';
      case 'manufacturing_order':
        return deleteWithEmptyPayload ||
                exists<ManufacturingOrder>(
                  _manufacturingOrders,
                  (item) => item.id,
                )
            ? null
            : 'manufacturing order ${change.entityId} was not stored locally';
      case 'purchase':
        return deleteWithEmptyPayload ||
                exists<Purchase>(_purchases, (item) => item.id)
            ? null
            : 'purchase ${change.entityId} was not stored locally';
      case 'account_transaction':
        return deleteWithEmptyPayload ||
                exists<AccountTransaction>(
                  _accountTransactions,
                  (item) => item.id,
                )
            ? null
            : 'account transaction ${change.entityId} was not stored locally';
      case 'stock_movement':
        return exists<StockMovement>(_stockMovements, (item) => item.id)
            ? null
            : 'stock movement ${change.entityId} was not stored locally';
    }
    return null;
  }

  Future<void> assertRemoteSyncChangesApplied(List<SyncChange> changes) async {
    final problems = <String>[];
    for (final change in changes) {
      final problem = _remoteSyncChangeApplyProblem(change);
      if (problem != null) problems.add('${change.id}: $problem');
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Remote sync apply verification failed: ${problems.take(5).join('; ')}',
      );
    }
  }

  Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) &&
          item.status != 'synced' &&
          item.status != 'rejected') {
        _syncQueue[i] = item.copyWith(
          status: 'submitted',
          lastError: '',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncChangesSyncedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    final matchedChangeIds = <String>{};
    for (var i = 0; i < _syncChanges.length; i++) {
      final change = _syncChanges[i];
      final matches = idSet.contains(change.id) ||
          idSet.contains(_syncMetaString(change, 'eventId')) ||
          idSet.contains(_syncMetaString(change, 'requestId')) ||
          idSet.contains(_syncMetaString(change, 'sourceCommandId'));
      if (matches) {
        matchedChangeIds.add(change.id);
        _syncChanges[i] = change.copyWith(isSynced: true, syncedAt: now);
      }
    }
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) ||
          matchedChangeIds.contains(item.changeId)) {
        _syncQueue[i] = item.copyWith(
          status: 'synced',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncQueueChangesInProgress(
    Iterable<String> changeIds,
  ) async {
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) &&
          _syncQueue[i].status != 'synced') {
        _syncQueue[i] = _syncQueue[i].copyWith(
          status: 'inProgress',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncChangesRejectedByIds(
    Map<String, String> rejected,
  ) async {
    if (rejected.isEmpty) return;
    final idSet = rejected.keys.toSet();
    final now = DateTime.now();
    var changed = false;
    final rejectedChanges = <SyncChange>[];
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      final reason = rejected[item.changeId];
      if (idSet.contains(item.changeId) &&
          item.status != 'synced' &&
          reason != null) {
        _syncQueue[i] = item.copyWith(
          status: 'rejected',
          lastError: reason,
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    for (var i = 0; i < _syncChanges.length; i++) {
      final change = _syncChanges[i];
      final matches = idSet.contains(change.id) ||
          idSet.contains(_syncMetaString(change, 'eventId')) ||
          idSet.contains(_syncMetaString(change, 'requestId')) ||
          idSet.contains(_syncMetaString(change, 'sourceCommandId'));
      if (matches) {
        rejectedChanges.add(change);
        _syncChanges[i] = change.copyWith(isSynced: true, syncedAt: now);
        changed = true;
      }
    }
    var quarantinedLocalCreate = false;
    if (rejectedChanges.isNotEmpty) {
      quarantinedLocalCreate = _quarantineRejectedLocalCreates(
        rejectedChanges,
        rejected,
        now,
      );
      changed = quarantinedLocalCreate || changed;
    }
    if (!changed) return;
    if (quarantinedLocalCreate) {
      await _saveDirty(
        products: true,
        customers: true,
        suppliers: true,
        supplierProductPrices: true,
        sync: true,
      );
    } else {
      await _saveSyncStateOnly();
    }
    notifyListeners();
  }

  bool _quarantineRejectedLocalCreates(
    List<SyncChange> rejectedChanges,
    Map<String, String> rejectedReasons,
    DateTime now,
  ) {
    var changed = false;
    for (final change in rejectedChanges) {
      // Only quarantine local creates/drafts. Remote authoritative changes must
      // never be deleted because of a status poll. The most common rejection in
      // the stress tests is duplicate product code/barcode; leaving that local
      // draft visible makes device counts diverge even though the Host rejected it.
      if (change.deviceId != _deviceId || change.operation == 'delete') {
        continue;
      }
      final reason = rejectedReasons[change.id] ??
          rejectedReasons[_syncMetaString(change, 'eventId')] ??
          rejectedReasons[_syncMetaString(change, 'requestId')] ??
          rejectedReasons[_syncMetaString(change, 'sourceCommandId')] ??
          'Rejected by Host.';
      switch (change.entityType) {
        case 'product':
          final index = _productIndexById[change.entityId];
          if (index != null && !_products[index].isDeleted) {
            _products[index] = _products[index].copyWith(
              isActive: false,
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              _productsKey,
              _products[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'customer':
          final index = _customers.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _customers[index] = _customers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              _customersKey,
              _customers[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'supplier':
          final index = _suppliers.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _suppliers[index] = _suppliers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              _suppliersKey,
              _suppliers[index].toJson(),
            );
            changed = true;
          }
          break;
        case 'supplier_product_price':
          final index = _supplierProductPrices.indexWhere(
            (item) => item.id == change.entityId && !item.isDeleted,
          );
          if (index >= 0) {
            _supplierProductPrices[index] =
                _supplierProductPrices[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(
              _supplierProductPricesKey,
              _supplierProductPrices[index].toJson(),
            );
            changed = true;
          }
          break;
      }
    }
    return changed;
  }

  Future<void> markSyncQueueChangesFailed(
    Iterable<String> changeIds,
    String error,
  ) async {
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) &&
          _syncQueue[i].status != 'synced') {
        final attempts = _syncQueue[i].attempts + 1;
        _syncQueue[i] = _syncQueue[i].copyWith(
          status: 'failed',
          attempts: attempts,
          lastError: error,
          updatedAt: now,
          // LAN sync should not block manual/auto retries for minutes.
          // A short backoff keeps reconnects responsive while still avoiding
          // a tight loop during brief network failures.
          nextRetryAt: now.add(Duration(seconds: (attempts * 5).clamp(5, 30))),
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> retryFailedSyncQueue({String? target}) async {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.status == 'failed' &&
          (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(
          status: 'pending',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> recoverStaleInProgressSyncQueue({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();
    final cutoff = now.subtract(staleAfter);
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (item.status == 'inProgress' &&
          item.updatedAt.isBefore(cutoff) &&
          (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(
          status: 'pending',
          lastError:
              'Recovered stale in-progress sync item after timeout/crash.',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncQueueItemFailed(String queueItemId, String error) async {
    final index = _syncQueue.indexWhere((item) => item.id == queueItemId);
    if (index == -1) return;
    final now = DateTime.now();
    final attempts = _syncQueue[index].attempts + 1;
    _syncQueue[index] = _syncQueue[index].copyWith(
      status: 'failed',
      attempts: attempts,
      lastError: error,
      updatedAt: now,
      nextRetryAt: now.add(Duration(minutes: attempts.clamp(1, 30))),
    );
    await _saveSyncStateOnly();
    notifyListeners();
  }

  @override
  void dispose() {
    _productDerivedDataFlushTimer?.cancel();
    unawaited(_flushProductDerivedData());
    unawaited(LocalDatabaseService.flushPendingWrites());
    super.dispose();
  }
}
