import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/local_database_service.dart';
import '../core/sync_unified/sync_device_state.dart';
import '../core/utils/currency_utils.dart';

import '../models/account_transaction.dart';
import '../models/catalog_item.dart';
import '../models/customer.dart';
import '../models/delivery_note.dart';
import '../models/manufacturing.dart';
import '../models/expense.dart';
import '../models/product.dart';
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
  derivator.init(pc.Pbkdf2Parameters(base64Url.decode(parts[2]), iterations, 32));
  final hash = derivator.process(Uint8List.fromList(utf8.encode('ventio|password|$password')));
  return storedHash == '$prefix$iterations:${parts[2]}:${base64UrlEncode(hash)}';
}

String _hashPasswordInBackground(Map<String, String> request) {
  const prefix = 'pbkdf2sha256:';
  final password = request['password'] ?? '';
  final salt = request['salt'] ?? '';
  final iterations = int.tryParse(request['iterations'] ?? '') ?? 210000;
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
  final hash = derivator.process(Uint8List.fromList(utf8.encode('ventio|password|$password')));
  return '$prefix$iterations:$salt:${base64UrlEncode(hash)}';
}

class BackupSummary {
  const BackupSummary({
    required this.version,
    required this.generatedAt,
    required this.productsCount,
    required this.customersCount,
    required this.salesCount,
    required this.suppliersCount,
    required this.expensesCount,
    required this.storeName,
  });

  final int version;
  final DateTime? generatedAt;
  final int productsCount;
  final int customersCount;
  final int salesCount;
  final int suppliersCount;
  final int expensesCount;
  final String storeName;
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

class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    required this.summary,
    this.errorMessage,
  });

  final bool isValid;
  final BackupSummary? summary;
  final String? errorMessage;
}

class BusinessDataIntegrityResult {
  const BusinessDataIntegrityResult({required this.ok, required this.message, this.problemCount = 0});
  final bool ok;
  final String message;
  final int problemCount;
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

class AppStore extends ChangeNotifier {
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
  static const _expensesKey = 'expenses_v4';
  static const _purchasesKey = 'purchases_v1';
  static const _stockMovementsKey = 'stock_movements_v1';
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
  static const _currentRoleKey = 'current_role_v1'; // legacy, no longer user-editable
  static const _rolesKey = 'roles_v1';
  static const _usersKey = 'users_v1';
  static const _activeUserKey = 'active_user_v1';
  static const _rememberLoginKey = 'remember_login_v1';
  static const _appIdentityKey = 'app_identity_v1';
  static const _themeModeKey = 'theme_mode_v1';
  static const _localeKey = 'locale_v1';
  static const _hostTransferApprovedDeviceKey = 'host_transfer_approved_device_v1';
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
  final List<CatalogItem> _categories = [];
  final List<CatalogItem> _brands = [];
  final List<CatalogItem> _units = [];
  final List<Expense> _expenses = [];
  final List<Purchase> _purchases = [];
  final List<StockMovement> _stockMovements = [];
  final List<Warehouse> _warehouses = [];
  final List<AccountTransaction> _accountTransactions = [];
  final Map<String, double> _accountBalanceCache = <String, double>{};
  final Map<String, List<AccountTransaction>> _accountTransactionsByAccountCache = <String, List<AccountTransaction>>{};
  bool _accountLedgerCacheDirty = true;
  final Map<String, Map<String, double>> _warehouseStockByProductCache = <String, Map<String, double>>{};
  bool _warehouseStockCacheDirty = true;
  final Map<String, List<SupplierPurchasePrice>> _purchaseHistoryByProductCache = <String, List<SupplierPurchasePrice>>{};
  final Map<String, _ProductPurchaseMetrics> _purchaseMetricsByProductCache = <String, _ProductPurchaseMetrics>{};
  bool _purchaseInsightsCacheDirty = true;
  final List<SyncChange> _syncChanges = [];
  final List<SyncQueueItem> _syncQueue = [];
  final List<SyncChange> _sqliteDirtySyncChanges = [];
  final List<SyncQueueItem> _sqliteDirtySyncQueue = [];
  final Map<String, Map<String, Map<String, dynamic>>> _sqliteDirtyBusinessRows = <String, Map<String, Map<String, dynamic>>>{};
  StoreProfile _storeProfile = StoreProfile.defaults;
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

  Customer get walkInCustomer => Customer(
        id: walkInCustomerId,
        name: walkInCustomerName,
        phone: '',
        address: '',
      );

  bool _isReady = false;

  bool get isReady => _isReady;
  List<Product> get products => List.unmodifiable(_products.where((item) => !item.isDeleted));
  List<Product> get allProductsForDiagnostics => List.unmodifiable(_products);
  List<Customer> get customers => List.unmodifiable(_customers.where((item) => !item.isDeleted));
  List<Sale> get sales => List.unmodifiable(_sales.where((item) => !item.isDeleted).toList().reversed);
  List<SaleQuotation> get saleQuotations => List.unmodifiable(_saleQuotations.where((item) => !item.isDeleted).toList().reversed);
  List<DeliveryNote> get deliveryNotes => List.unmodifiable(_deliveryNotes.where((item) => !item.isDeleted).toList().reversed);
  List<BillOfMaterials> get billsOfMaterials => List.unmodifiable(_billsOfMaterials.where((item) => !item.isDeleted && item.isActive).toList().reversed);
  List<ManufacturingOrder> get manufacturingOrders => List.unmodifiable(_manufacturingOrders.where((item) => !item.isDeleted).toList().reversed);
  List<Supplier> get suppliers => List.unmodifiable(_suppliers.where((item) => !item.isDeleted));
  List<SupplierProductPrice> get supplierProductPrices => List.unmodifiable(_supplierProductPrices.where((item) => !item.isDeleted));
  List<SupplierProductPrice> get allSupplierProductPricesForDiagnostics => List.unmodifiable(_supplierProductPrices);
  List<CatalogItem> get categories => List.unmodifiable(_categories.where((item) => !item.isDeleted));
  List<CatalogItem> get brands => List.unmodifiable(_brands.where((item) => !item.isDeleted));
  List<CatalogItem> get units => List.unmodifiable(_units.where((item) => !item.isDeleted));
  List<DataConflict> get dataConflicts => List.unmodifiable(_detectDataConflicts());
  int get dataConflictCount => dataConflicts.length;
  int get blockingDataConflictCount => dataConflicts.where((item) => item.blocking).length;
  List<Expense> get expenses => List.unmodifiable(_expenses.where((item) => !item.isDeleted).toList().reversed);
  List<Purchase> get purchases => List.unmodifiable(_purchases.where((item) => !item.isDeleted).toList().reversed);
  List<StockMovement> get stockMovements => List.unmodifiable(_stockMovements.toList().reversed);
  List<Warehouse> get warehouses => List.unmodifiable(_warehouses.where((item) => !item.isDeleted && item.isActive));

  Warehouse get defaultWarehouse {
    _ensureDefaultWarehouse();
    return _warehouses.firstWhere((item) => item.id == Warehouse.defaultId, orElse: () => Warehouse(id: Warehouse.defaultId, name: Warehouse.defaultName, isDefault: true));
  }

  void _ensureDefaultWarehouse() {
    if (_warehouses.any((item) => item.id == Warehouse.defaultId && !item.isDeleted)) return;
    final now = DateTime.now();
    _warehouses.insert(0, Warehouse(
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
    ));
  }

  void _invalidateDerivedDataCaches() {
    _warehouseStockCacheDirty = true;
    _purchaseInsightsCacheDirty = true;
  }

  @override
  void notifyListeners() {
    _invalidateDerivedDataCaches();
    super.notifyListeners();
  }

  void _ensureWarehouseStockCache() {
    if (!_warehouseStockCacheDirty) return;
    _ensureDefaultWarehouse();
    final warehouseIds = _warehouses.where((item) => !item.isDeleted).map((item) => item.id).toList(growable: false);
    _warehouseStockByProductCache.clear();
    for (final product in _products.where((item) => !item.isDeleted)) {
      _warehouseStockByProductCache[product.id] = <String, double>{for (final id in warehouseIds) id: 0};
    }

    for (final movement in _stockMovements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      final wid = movement.warehouseId.trim().isEmpty ? Warehouse.defaultId : movement.warehouseId.trim();
      final result = _warehouseStockByProductCache.putIfAbsent(productId, () => <String, double>{for (final id in warehouseIds) id: 0});
      result[wid] = (result[wid] ?? 0) + movement.quantity;
    }

    for (final product in _products.where((item) => !item.isDeleted)) {
      final result = _warehouseStockByProductCache.putIfAbsent(product.id, () => <String, double>{for (final id in warehouseIds) id: 0});
      final assigned = result.values.fold<double>(0, (sum, value) => sum + value);
      final unassignedLegacyStock = product.stock - assigned;
      if (unassignedLegacyStock != 0) {
        result[Warehouse.defaultId] = (result[Warehouse.defaultId] ?? 0) + unassignedLegacyStock;
      }
    }
    _warehouseStockCacheDirty = false;
  }

  double stockForWarehouse(String productId, String warehouseId) {
    _ensureWarehouseStockCache();
    final wid = warehouseId.trim().isEmpty ? Warehouse.defaultId : warehouseId.trim();
    return _warehouseStockByProductCache[productId]?[wid] ?? 0;
  }

  Map<String, double> warehouseStockForProduct(String productId) {
    _ensureWarehouseStockCache();
    return Map.unmodifiable(_warehouseStockByProductCache[productId] ?? const <String, double>{});
  }
  List<AccountTransaction> get accountTransactions => List.unmodifiable(_accountTransactions.where((item) => !item.isDeleted).toList().reversed);

  String _accountLedgerKey(String accountType, String accountId) => '${accountType.trim().toLowerCase()}::${accountId.trim()}';

  void _invalidateAccountLedgerCache() {
    _accountLedgerCacheDirty = true;
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
      _accountBalanceCache[key] = (_accountBalanceCache[key] ?? 0) + item.signedAmount;
      (_accountTransactionsByAccountCache[key] ??= <AccountTransaction>[]).add(item);
    }
    for (final rows in _accountTransactionsByAccountCache.values) {
      rows.sort((a, b) => b.date.compareTo(a.date));
    }
    _accountLedgerCacheDirty = false;
  }

  List<AccountTransaction> accountTransactionsForAccount(String accountType, String accountId) {
    _ensureAccountLedgerCache();
    return List.unmodifiable(_accountTransactionsByAccountCache[_accountLedgerKey(accountType, accountId)] ?? const <AccountTransaction>[]);
  }

  double accountBalance(String accountType, String accountId) {
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
        return List.unmodifiable(_products.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'customers':
        return List.unmodifiable(_customers.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'suppliers':
        return List.unmodifiable(_suppliers.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'supplierProductPrices':
        return List.unmodifiable(_supplierProductPrices.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'expenses':
        return List.unmodifiable(_expenses.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'categories':
        return List.unmodifiable(_categories.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'brands':
        return List.unmodifiable(_brands.where((item) => !item.isDeleted).map((item) => item.toJson()));
      case 'units':
        return List.unmodifiable(_units.where((item) => !item.isDeleted).map((item) => item.toJson()));
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
        await addOrUpdateSupplierProductPrice(SupplierProductPrice.fromJson(json));
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

  Future<void> _deleteCatalogItem(List<CatalogItem> list, String entityType, String id, {bool categories = false, bool brands = false, bool units = false}) async {
    requirePermission(AppPermission.catalogManage);
    final index = list.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    list[index] = _withSyncMeta<CatalogItem>(list[index].copyWith(deletedAt: now), now, clearDeletedAt: false);
    _recordSyncChange(entityType: entityType, entityId: id, operation: 'delete', payload: list[index].toJson());
    await _saveDirty(categories: categories, brands: brands, units: units, sync: true);
    notifyListeners();
  }
  List<SyncChange> get syncChanges => List.unmodifiable(_syncChanges);
  int get currentSyncSequence => _syncSequence;
  List<SyncQueueItem> get syncQueue => List.unmodifiable(_syncQueue);
  List<SyncQueueItem> get pendingSyncQueue => List.unmodifiable(_syncQueue.where((item) => item.isPending));
  List<SyncChange> get pendingSyncChanges => List.unmodifiable(_syncChanges.where((item) => !item.isSynced));
  List<SyncQueueItem> pendingSyncQueueForTarget(String target, {bool readyOnly = true}) {
    final items = _syncQueue.where((item) => item.target == target && item.isPending);
    return List.unmodifiable(readyOnly ? items.where((item) => item.isReadyToSend) : items);
  }

  List<SyncChange> pendingSyncChangesForTarget(String target, {bool readyOnly = true}) {
    final queueItems = pendingSyncQueueForTarget(target, readyOnly: readyOnly);
    final ids = queueItems.map((item) => item.changeId).toSet();
    return List.unmodifiable(_syncChanges.where((change) => ids.contains(change.id) && !change.isSynced));
  }

  List<SyncChange> submittedSyncChangesForTarget(String target) {
    final ids = _syncQueue
        .where((item) => item.target == target && item.status == 'submitted')
        .map((item) => item.changeId)
        .toSet();
    return List.unmodifiable(_syncChanges.where((change) => ids.contains(change.id) && !change.isSynced));
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
    final target = activeClientSyncTarget;
    if (target.isEmpty) return pendingSyncCount;
    return pendingSyncQueueForTarget(target, readyOnly: false).length;
  }
  DateTime? get latestResetSyncAt {
    DateTime? latest;
    for (final change in _syncChanges) {
      if (change.entityType == 'system' && change.operation == 'reset_store_data') {
        if (latest == null || change.createdAt.isAfter(latest)) latest = change.createdAt;
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
  AppIdentity get appIdentity => _appIdentity ?? AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform());
  UserRole? get currentUserRole => _activeUser == null ? null : roleById(_activeUser!.roleId);
  bool get isAdmin => _activeUser?.roleId == 'admin' || currentUserRole?.isAdmin == true;
  bool get canSell => hasPermission(AppPermission.salesCreate);
  bool get canManageProducts => hasPermission(AppPermission.productsCreate) || hasPermission(AppPermission.productsEdit);
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  bool get canManageUsers => hasPermission(AppPermission.usersManage) && hasPermission(AppPermission.rolesManage);
  bool get needsInitialAdminSetup => _users.isEmpty || _hasOnlyLegacyDefaultAdminUser;
  bool get isSuspendedByHost => appIdentity.isClient && ClientSuspensionStateStore.isSuspended;
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
    return ThemeMode.values.firstWhere((mode) => mode.name == raw, orElse: () => ThemeMode.system);
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await LocalDatabaseService.setString(_themeModeKey, mode.name);
  }

  Future<Locale> loadLocale() async {
    final raw = LocalDatabaseService.getString(_localeKey) ?? 'en';
    return ['en', 'ar'].contains(raw) ? Locale(raw) : const Locale('en');
  }

  Future<void> saveLocale(Locale locale) async {
    final languageCode = ['en', 'ar'].contains(locale.languageCode) ? locale.languageCode : 'en';
    await LocalDatabaseService.setString(_localeKey, languageCode);
  }


  Map<String, dynamic> _loadDevFeatureFlags() {
    final raw = LocalDatabaseService.getString(_devFeatureFlagsKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
      if (decoded is Map) return decoded.map((key, value) => MapEntry(key.toString(), value));
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
    await LocalDatabaseService.setString(_devFeatureFlagsKey, jsonEncode(flags));
    notifyListeners();
  }


  bool get _hasOnlyLegacyDefaultAdminUser {
    if (_users.length != 1) return false;
    final user = _users.first;
    final legacyPassword = String.fromCharCodes(const [97, 100, 109, 105, 110, 49, 50, 51]);
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
    if (cleanUsername.length < 3) throw ArgumentError('Username must be at least 3 characters.');
    if (cleanPassword.length < 6) throw ArgumentError('Password must be at least 6 characters.');
    if (_users.isNotEmpty && !_hasOnlyLegacyDefaultAdminUser) {
      throw StateError('Initial administrator setup is already complete.');
    }
    final now = DateTime.now();
    final platform = _detectPlatform();
    if (platform == AppPlatformType.web) {
      throw StateError('Web devices cannot create a Host. Use Connect to Store from Web.');
    }
    final legacyIndex = _hasOnlyLegacyDefaultAdminUser ? 0 : -1;
    if (legacyIndex == -1 && _users.any((user) => user.username.trim().toLowerCase() == cleanUsername)) {
      throw StateError('Username already exists.');
    }
    final passwordHash = await _hashPasswordAsync(cleanPassword);
    final hostIdentity = _normalizedLocalIdentity(appIdentity.copyWith(
      deviceRole: DeviceRole.host,
      syncMode: appIdentity.syncMode == SyncMode.cloudConnected || appIdentity.syncMode == SyncMode.marketplaceEnabled
          ? appIdentity.syncMode
          : SyncMode.lanOnly,
      hostDeviceId: '',
      platform: platform,
      updatedAt: now,
    ));
    _assertSafeRoleTransition(hostIdentity, source: 'initial Host registration', allowInitialHostRegistration: true);
    _assertLanCloudRoleRules(hostIdentity, source: 'initial Host registration');
    _appIdentity = hostIdentity;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(hostIdentity.toJson()));
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
    final effective = <String>{...?role?.permissions, ..._activeUser!.extraPermissions};
    effective.removeAll(_activeUser!.deniedPermissions);
    return effective.contains(permission);
  }

  void requirePermission(String permission) {
    if (!hasPermission(permission)) {
      throw StateError('You do not have permission: $permission');
    }
  }

  double get totalSalesAmount => sales.fold<double>(0, (sum, sale) => sum + sale.total);
  double get totalExpensesAmount => expenses.where((item) => item.isPosted).fold<double>(0, (sum, expense) => sum + expense.amount);
  double get totalPurchasesAmount => purchases.where((item) => !item.isCancelled).fold<double>(0, (sum, purchase) => sum + purchase.subtotal);
  int get pendingPurchaseCount => purchases.where((item) => item.status.toLowerCase() == 'draft').length;

  void _ensurePurchaseInsightsCache() {
    if (!_purchaseInsightsCacheDirty) return;
    _purchaseHistoryByProductCache.clear();
    _purchaseMetricsByProductCache.clear();

    for (final purchase in _purchases.where((item) => !item.isDeleted && !item.isCancelled)) {
      for (final item in purchase.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        (_purchaseHistoryByProductCache[productId] ??= <SupplierPurchasePrice>[]).add(SupplierPurchasePrice(
          productId: item.productId,
          productName: item.productName,
          supplierId: purchase.supplierId,
          supplierName: purchase.supplierName,
          unitCost: item.unitCostPerBase,
          quantity: item.baseQuantity,
          purchaseId: purchase.id,
          purchaseNo: purchase.purchaseNo,
          date: purchase.date,
        ));
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
    return List.unmodifiable(_purchaseHistoryByProductCache[productId] ?? const <SupplierPurchasePrice>[]);
  }

  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    final latestBySupplier = <String, SupplierPurchasePrice>{};
    for (final entry in _purchaseHistoryByProductCache[productId] ?? const <SupplierPurchasePrice>[]) {
      latestBySupplier.putIfAbsent(entry.supplierId, () => entry);
    }
    final prices = latestBySupplier.values.toList()..sort((a, b) => a.unitCost.compareTo(b.unitCost));
    return List.unmodifiable(prices);
  }

  double? lastPurchasePriceFor({required String productId, required String supplierId}) {
    _ensurePurchaseInsightsCache();
    for (final entry in _purchaseHistoryByProductCache[productId] ?? const <SupplierPurchasePrice>[]) {
      if (entry.supplierId == supplierId) return entry.unitCost;
    }
    return null;
  }

  double? lastPurchasePriceForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return _purchaseMetricsByProductCache[productId]?.lastCost;
  }

  PurchaseItem? lastPurchaseItemFor({required String productId, required String supplierId}) {
    final sortedPurchases = _purchases.where((purchase) => !purchase.isDeleted && !purchase.isCancelled && purchase.supplierId == supplierId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId == productId) return item;
      }
    }
    return null;
  }

  PurchaseItem? lastPurchaseItemForProduct(String productId) {
    final sortedPurchases = _purchases.where((purchase) => !purchase.isDeleted && !purchase.isCancelled).toList()
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
    final sortedPurchases = _purchases.where((item) => !item.isDeleted && !item.isCancelled).toList()
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

  int _seedSupplierProductPricesFromLegacyProductSuppliers({bool recordSyncChanges = false}) {
    final supplierByLegacyName = <String, Supplier>{};
    for (final supplier in _suppliers.where((item) => !item.isDeleted)) {
      for (final name in <String>[supplier.name, supplier.nameEn, supplier.nameAr, supplier.id]) {
        final key = _normalizeLegacySupplierName(name);
        if (key.isNotEmpty) supplierByLegacyName.putIfAbsent(key, () => supplier);
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
      final supplier = supplierByLegacyName[_normalizeLegacySupplierName(legacySupplierName)];
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
        storeId: product.storeId.isNotEmpty ? product.storeId : appIdentity.storeId,
        branchId: product.branchId.isNotEmpty ? product.branchId : appIdentity.branchId,
        version: 1,
        lastModifiedByDeviceId: product.lastModifiedByDeviceId.isNotEmpty ? product.lastModifiedByDeviceId : _deviceId,
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
    for (final item in _supplierProductPrices.where((item) => !item.isDeleted)) {
      productSupplierCounts[item.productId] = (productSupplierCounts[item.productId] ?? 0) + 1;
    }
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (!item.isDeleted && productSupplierCounts[item.productId] == 1 && !item.isPreferred) {
        _supplierProductPrices[i] = item.copyWith(isPreferred: true);
      }
    }
  }

  String _normalizeLegacySupplierName(String value) => value.trim().toLowerCase();

  String _supplierProductPriceId(String productId, String supplierId) {
    final cleanProductId = productId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final cleanSupplierId = supplierId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
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

  List<SupplierProductPrice> supplierProductPricesForSupplier(String supplierId) {
    final rows = _supplierProductPrices
        .where((item) => !item.isDeleted && item.supplierId == supplierId)
        .toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    return List.unmodifiable(rows);
  }

  SupplierProductPrice? supplierProductPriceFor({required String productId, required String supplierId}) {
    for (final item in _supplierProductPrices) {
      if (!item.isDeleted && item.productId == productId && item.supplierId == supplierId) return item;
    }
    return null;
  }

  SupplierProductPrice? preferredSupplierProductPriceForProduct(String productId) {
    final rows = supplierProductPricesForProduct(productId);
    for (final item in rows) {
      if (item.isPreferred) return item;
    }
    return rows.isEmpty ? null : rows.first;
  }

  SupplierProductPrice? bestPriceSupplierProductPriceForProduct(String productId) {
    final rows = supplierProductPricesForProduct(productId);
    if (rows.isEmpty) return null;
    final sorted = rows.toList()..sort((a, b) => a.cost.compareTo(b.cost));
    return sorted.first;
  }

  SupplierProductPrice? fastestSupplierProductPriceForProduct(String productId) {
    final rows = supplierProductPricesForProduct(productId).where((item) => item.leadTimeDays != null).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.leadTimeDays!.compareTo(b.leadTimeDays!));
    return rows.first;
  }

  Future<void> addOrUpdateSupplierProductPrice(SupplierProductPrice price) async {
    requirePermission(AppPermission.suppliersManage);
    final cleanProductId = price.productId.trim();
    final cleanSupplierId = price.supplierId.trim();
    if (cleanProductId.isEmpty || cleanSupplierId.isEmpty) {
      throw ArgumentError('Product and supplier are required for supplier price.');
    }
    if (price.cost < 0) {
      throw ArgumentError('Supplier price cannot be negative.');
    }
    final now = DateTime.now();
    final existingIndex = _supplierProductPrices.indexWhere((item) => item.id == price.id);
    final duplicateIndex = _supplierProductPrices.indexWhere((item) =>
        item.id != price.id &&
        !item.isDeleted &&
        item.productId == cleanProductId &&
        item.supplierId == cleanSupplierId);
    final id = price.id.trim().isNotEmpty
        ? price.id.trim()
        : 'spp_${cleanProductId}_${cleanSupplierId}_${now.microsecondsSinceEpoch}';
    final previous = existingIndex != -1
        ? _supplierProductPrices[existingIndex]
        : (duplicateIndex != -1 ? _supplierProductPrices[duplicateIndex] : null);
    final nextCurrency = price.currency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    final history = List<SupplierProductPriceHistoryEntry>.from(price.priceHistory);
    if (previous != null &&
        ((previous.cost - price.cost).abs() > 0.0001 || previous.currency.toUpperCase() != nextCurrency)) {
      history.add(SupplierProductPriceHistoryEntry(
        oldCost: previous.cost,
        newCost: price.cost,
        currency: nextCurrency,
        changedAt: now,
        source: 'manual',
      ));
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
        if (!item.isDeleted && item.productId == cleanProductId && item.id != normalized.id && item.isPreferred) {
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
      normalized = normalized.copyWith(id: _supplierProductPrices[duplicateIndex].id, createdAt: _supplierProductPrices[duplicateIndex].createdAt);
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
  int get lowStockCount => products.where((product) => product.trackStock && product.isLowStock).length;
  List<Product> get stockTrackedProducts => products.where((product) => product.trackStock).toList(growable: false);
  double get totalUnitsInStock => stockTrackedProducts.fold<double>(0, (sum, item) => sum + item.stock);
  double get inventoryRetailValue => stockTrackedProducts.fold<double>(0, (sum, item) => sum + (item.usdPrice * item.stock));
  double get inventoryCostValue => stockTrackedProducts.fold<double>(0, (sum, item) => sum + (_safeUsdCost(item) * item.stock));

  Future<void> initialize() async {
    await _migrateLegacySharedPreferencesIfNeeded();
    await _ensureDeviceId();

    final schemaVersion = int.tryParse(LocalDatabaseService.getString(_schemaVersionKey) ?? '') ?? 0;
    final canUseFastStartup = LocalDatabaseService.isSqliteAuthoritative && schemaVersion >= 17;

    if (canUseFastStartup) {
      // Startup performance fix: do not hydrate every large business table while
      // the splash/login shell is opening. The SQLite service now mirrors only
      // scalar keys plus small login/catalog lists. Large lists are loaded right
      // after startup and the UI is notified when they become available.
      _categories
        ..clear()
        ..addAll(_loadCatalogItems(_categoriesKey));
      _brands
        ..clear()
        ..addAll(_loadCatalogItems(_brandsKey));
      _units
        ..clear()
        ..addAll(_loadCatalogItems(_unitsKey));
      _storeProfile = _loadStoreProfile();
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
      _rememberLogin = LocalDatabaseService.getString(_rememberLoginKey) == 'true';
      _restoreActiveUser();
      _appIdentity = _loadOrCreateAppIdentity();
      _syncSequence = int.tryParse(LocalDatabaseService.getString(_syncSequenceKey) ?? '') ?? 0;
      _ensureCatalogDefaults();

      _isReady = true;
      notifyListeners();
      unawaited(_loadDeferredStartupData());
      return;
    }

    _products
      ..clear()
      ..addAll(_loadProducts());
    _customers
      ..clear()
      ..addAll(_loadCustomers());
    _sales
      ..clear()
      ..addAll(_loadSales());
    _saleQuotations
      ..clear()
      ..addAll(_loadSaleQuotations());
    _deliveryNotes
      ..clear()
      ..addAll(_loadDeliveryNotes());
    _billsOfMaterials
      ..clear()
      ..addAll(_loadBillsOfMaterials());
    _manufacturingOrders
      ..clear()
      ..addAll(_loadManufacturingOrders());
    _suppliers
      ..clear()
      ..addAll(_loadSuppliers());
    _supplierProductPrices
      ..clear()
      ..addAll(_loadSupplierProductPrices());
    _categories
      ..clear()
      ..addAll(_loadCatalogItems(_categoriesKey));
    _brands
      ..clear()
      ..addAll(_loadCatalogItems(_brandsKey));
    _units
      ..clear()
      ..addAll(_loadCatalogItems(_unitsKey));
    _expenses
      ..clear()
      ..addAll(_loadExpenses());
    _purchases
      ..clear()
      ..addAll(_loadPurchases());
    _stockMovements
      ..clear()
      ..addAll(_loadStockMovements());
    _warehouses
      ..clear()
      ..addAll(_loadWarehouses());
    _ensureDefaultWarehouse();
    _accountTransactions
      ..clear()
      ..addAll(_loadAccountTransactions());
    _invalidateAccountLedgerCache();
    _syncChanges
      ..clear()
      ..addAll(_loadSyncChanges());
    _syncQueue
      ..clear()
      ..addAll(_loadSyncQueue());
    _storeProfile = _loadStoreProfile();
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
    _rememberLogin = LocalDatabaseService.getString(_rememberLoginKey) == 'true';
    _restoreActiveUser();
    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();
    _normalizeCustomers();
    _ensureCatalogDefaults();
    await _runDataMigrationsIfNeeded();

    _isReady = true;
    notifyListeners();
  }

  Future<String?> _loadEntityListJsonForStartup(String key) {
    return LocalDatabaseService.getBusinessEntityListJson(key);
  }

  Future<List<T>> _decodeDeferredList<T>(String key, T Function(Map<String, dynamic>) fromJson) async {
    var raw = await _loadEntityListJsonForStartup(key);
    raw ??= LocalDatabaseService.getString(key);
    if (raw == null || raw.isEmpty) return <T>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  Future<void> _loadDeferredStartupData() async {
    try {
      final results = await Future.wait<List<dynamic>>(<Future<List<dynamic>>>[
        _decodeDeferredList<Product>(_productsKey, Product.fromJson),
        _decodeDeferredList<Customer>(_customersKey, Customer.fromJson),
        _decodeDeferredList<Sale>(_salesKey, Sale.fromJson),
        _decodeDeferredList<SaleQuotation>(_saleQuotationsKey, SaleQuotation.fromJson),
        _decodeDeferredList<DeliveryNote>(_deliveryNotesKey, DeliveryNote.fromJson),
        _decodeDeferredList<BillOfMaterials>(_billsOfMaterialsKey, BillOfMaterials.fromJson),
        _decodeDeferredList<ManufacturingOrder>(_manufacturingOrdersKey, ManufacturingOrder.fromJson),
        _decodeDeferredList<Supplier>(_suppliersKey, Supplier.fromJson),
        _decodeDeferredList<SupplierProductPrice>(_supplierProductPricesKey, SupplierProductPrice.fromJson),
        _decodeDeferredList<Expense>(_expensesKey, Expense.fromJson),
        _decodeDeferredList<Purchase>(_purchasesKey, Purchase.fromJson),
        _decodeDeferredList<StockMovement>(_stockMovementsKey, StockMovement.fromJson),
        _decodeDeferredList<Warehouse>(_warehousesKey, Warehouse.fromJson),
        _decodeDeferredList<AccountTransaction>(_accountTransactionsKey, AccountTransaction.fromJson),
        _decodeDeferredList<SyncChange>(_syncChangesKey, SyncChange.fromJson),
        _decodeDeferredList<SyncQueueItem>(_syncQueueKey, SyncQueueItem.fromJson),
      ]);

      _products
        ..clear()
        ..addAll(results[0].cast<Product>());
      _customers
        ..clear()
        ..addAll(results[1].cast<Customer>());
      _sales
        ..clear()
        ..addAll(results[2].cast<Sale>());
      _saleQuotations
        ..clear()
        ..addAll(results[3].cast<SaleQuotation>());
      _deliveryNotes
        ..clear()
        ..addAll(results[4].cast<DeliveryNote>());
      _billsOfMaterials
        ..clear()
        ..addAll(results[5].cast<BillOfMaterials>());
      _manufacturingOrders
        ..clear()
        ..addAll(results[6].cast<ManufacturingOrder>());
      _suppliers
        ..clear()
        ..addAll(results[7].cast<Supplier>());
      _supplierProductPrices
        ..clear()
        ..addAll(results[8].cast<SupplierProductPrice>());
      _expenses
        ..clear()
        ..addAll(results[9].cast<Expense>());
      _purchases
        ..clear()
        ..addAll(results[10].cast<Purchase>());
      _stockMovements
        ..clear()
        ..addAll(results[11].cast<StockMovement>());
      _warehouses
        ..clear()
        ..addAll(results[12].cast<Warehouse>());
      _accountTransactions
        ..clear()
        ..addAll(results[13].cast<AccountTransaction>());
      _syncChanges
        ..clear()
        ..addAll(results[14].cast<SyncChange>());
      _syncQueue
        ..clear()
        ..addAll(results[15].cast<SyncQueueItem>());
      _ensureDefaultWarehouse();

      _normalizeCustomers();
      _ensureCatalogDefaults();
      _invoiceCounter = _loadInvoiceCounter();
      _purchaseCounter = _loadPurchaseCounter();
      _syncSequence = _loadSyncSequence();
      _invalidateAccountLedgerCache();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Deferred startup data load failed: $error');
      debugPrint('$stackTrace');
    }
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

    final legacyProducts = prefs.getString('products_v3') ?? prefs.getString('products_v2');
    final legacyCustomers = prefs.getString('customers_v3') ?? prefs.getString('customers_v2');
    final legacySales = prefs.getString('sales_v3') ?? prefs.getString('sales_v2');
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
      await LocalDatabaseService.setString(_storeProfileKey, legacyStoreProfile);
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
    final body = List<String>.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '${prefix.toUpperCase()}-$body';
  }

  String _normalizeGeneratedId(String value, {required String fallbackPrefix}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return _generatePrefixedId(fallbackPrefix);
    final parts = trimmed.split('-');
    if (parts.length == 2) {
      final rawPrefix = parts.first.toUpperCase();
      final prefix = rawPrefix == 'DEV' || rawPrefix == 'Dev'.toUpperCase() ? 'DV' : rawPrefix;
      final body = parts.last.toUpperCase();
      return '$prefix-$body';
    }
    return trimmed.toUpperCase();
  }

  List<Product> _loadProducts() {
    final raw = LocalDatabaseService.getString(_productsKey);
    if (raw == null) return <Product>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<Customer> _loadCustomers() {
    final raw = LocalDatabaseService.getString(_customersKey);
    if (raw == null) return <Customer>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Customer.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<SaleQuotation> _loadSaleQuotations() {
    final raw = LocalDatabaseService.getString(_saleQuotationsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<DeliveryNote> _loadDeliveryNotes() {
    final raw = LocalDatabaseService.getString(_deliveryNotesKey);
    if (raw == null || raw.isEmpty) return <DeliveryNote>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<BillOfMaterials> _loadBillsOfMaterials() {
    final raw = LocalDatabaseService.getString(_billsOfMaterialsKey);
    if (raw == null || raw.isEmpty) return <BillOfMaterials>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => BillOfMaterials.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<ManufacturingOrder> _loadManufacturingOrders() {
    final raw = LocalDatabaseService.getString(_manufacturingOrdersKey);
    if (raw == null || raw.isEmpty) return <ManufacturingOrder>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => ManufacturingOrder.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<Sale> _loadSales() {
    final raw = LocalDatabaseService.getString(_salesKey);
    if (raw == null) return <Sale>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<Supplier> _loadSuppliers() {
    final raw = LocalDatabaseService.getString(_suppliersKey);
    if (raw == null) return <Supplier>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }


  List<SupplierProductPrice> _loadSupplierProductPrices() {
    final raw = LocalDatabaseService.getString(_supplierProductPricesKey);
    if (raw == null) return <SupplierProductPrice>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => SupplierProductPrice.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<Purchase> _loadPurchases() {
    final raw = LocalDatabaseService.getString(_purchasesKey);
    if (raw == null) return <Purchase>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<StockMovement> _loadStockMovements() {
    final raw = LocalDatabaseService.getString(_stockMovementsKey);
    if (raw == null) return <StockMovement>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => StockMovement.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }


  List<Warehouse> _loadWarehouses() {
    final raw = LocalDatabaseService.getString(_warehousesKey);
    if (raw == null) return <Warehouse>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }


  List<AccountTransaction> _loadAccountTransactions() {
    final raw = LocalDatabaseService.getString(_accountTransactionsKey);
    if (raw == null) return <AccountTransaction>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => AccountTransaction.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }


  List<CatalogItem> _loadCatalogItems(String key) {
    final raw = LocalDatabaseService.getString(key);
    if (raw == null) return <CatalogItem>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  void _ensureCatalogDefaults() {
    if (_categories.isEmpty) {
      _categories.add(CatalogItem(id: 'cat_general', nameEn: 'General', nameAr: 'عام', code: 'General'));
    }
    if (_brands.isEmpty) {
      _brands.add(CatalogItem(id: 'brand_generic', nameEn: 'Generic', nameAr: 'عام', code: 'Generic'));
    }
    if (_units.isEmpty) {
      _units.addAll([
        CatalogItem(id: 'unit_pcs', nameEn: 'Piece', nameAr: 'قطعة', code: 'pcs'),
        CatalogItem(id: 'unit_box', nameEn: 'Box', nameAr: 'علبة', code: 'box'),
        CatalogItem(id: 'unit_pack', nameEn: 'Pack', nameAr: 'باكيت', code: 'pack'),
        CatalogItem(id: 'unit_kg', nameEn: 'Kilogram', nameAr: 'كيلوغرام', code: 'kg'),
        CatalogItem(id: 'unit_g', nameEn: 'Gram', nameAr: 'غرام', code: 'g'),
        CatalogItem(id: 'unit_l', nameEn: 'Liter', nameAr: 'ليتر', code: 'L'),
        CatalogItem(id: 'unit_ml', nameEn: 'Milliliter', nameAr: 'ميليلتر', code: 'ml'),
        CatalogItem(id: 'unit_m', nameEn: 'Meter', nameAr: 'متر', code: 'm'),
      ]);
    }
    _seedCatalogFromProducts(_categories, _products.map((item) => item.category));
    _seedCatalogFromProducts(_brands, _products.map((item) => item.brand));
    _seedCatalogFromProducts(_units, _products.map((item) => item.unit));
  }

  void _seedCatalogFromProducts(List<CatalogItem> target, Iterable<String> values) {
    final used = target.map((item) => item.nameEn.trim().toLowerCase()).toSet();
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty || used.contains(value.toLowerCase())) continue;
      target.add(CatalogItem(id: DateTime.now().microsecondsSinceEpoch.toString() + target.length.toString(), nameEn: value, nameAr: '', code: value));
      used.add(value.toLowerCase());
    }
  }

  List<SyncChange> _loadSyncChanges() {
    final raw = LocalDatabaseService.getString(_syncChangesKey);
    if (raw == null) return <SyncChange>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }


  int _loadSyncSequence() {
    final stored = int.tryParse(LocalDatabaseService.getString(_syncSequenceKey) ?? '') ?? 0;
    final highest = _syncChanges.fold<int>(0, (value, change) => change.sequence > value ? change.sequence : value);
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
    return Map<String, dynamic>.from(change.payload['_syncV2'] as Map? ?? const {});
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
    if (sourceCommandId.isNotEmpty && acceptedSourceCommandIds.contains(sourceCommandId)) return true;

    // Host sequence is the authoritative ordering guard. If this device has
    // already applied a newer/equal Host sequence, the incoming event is a
    // replay from an old cursor/page and must not be applied again.
    if (change.sequence > 0 && lastAppliedSequence > 0 && change.sequence <= lastAppliedSequence) {
      return true;
    }

    return false;
  }


  String? validateClientDraftForHostAcceptance(SyncChange change) {
    if (change.entityType == 'system' && change.operation == 'reset_store_data') {
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
          final sameBarcode = barcode.isNotEmpty && item.barcode.trim().toLowerCase() == barcode;
          return sameCode || sameBarcode;
        });
        if (duplicate) return 'Product code or barcode already exists on the Host.';
        return null;
      case 'sale':
        final invoiceNo = (p['invoiceNo'] ?? p['invoice_no'] ?? '').toString().trim().toLowerCase();
        if (invoiceNo.isEmpty) return null;
        final duplicate = _sales.any((item) => item.id != change.entityId && !item.isDeleted && item.invoiceNo.trim().toLowerCase() == invoiceNo);
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
    return decoded.map((item) => SyncQueueItem.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<Expense> _loadExpenses() {
    final raw = LocalDatabaseService.getString(_expensesKey);
    if (raw == null) return <Expense>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map))).toList();
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
    final current = int.tryParse(LocalDatabaseService.getString(_schemaVersionKey) ?? '') ?? 0;
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
      _seedSupplierProductPricesFromLegacyProductSuppliers(recordSyncChanges: true);
    }

    if (current < 15 && LocalDatabaseService.getString(_supplierProductPricesKey) == null) {
      await LocalDatabaseService.setString(_supplierProductPricesKey, jsonEncode(_supplierProductPrices.map((item) => item.toJson()).toList()));
    }

    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();

    await LocalDatabaseService.setString(_syncSequenceKey, _syncSequence.toString());
    await LocalDatabaseService.setString(_schemaVersionKey, '17');
    await LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString());
    await LocalDatabaseService.setString(_purchaseCounterKey, _purchaseCounter.toString());
    await _saveAll();
  }

  double _safeUsdCost(Product product) {
    final usdCost = product.usdCost.isFinite && product.usdCost >= 0 ? product.usdCost : 0.0;
    final originalCost = product.originalCost.isFinite && product.originalCost >= 0 ? product.originalCost : 0.0;
    final rawCost = product.cost.isFinite && product.cost >= 0 ? product.cost : 0.0;
    if (product.costCurrency.toUpperCase() != 'LBP') {
      return usdCost;
    }

    final sourceLbpCost = originalCost > 0 ? originalCost : (rawCost > 0 ? rawCost : usdCost);
    final expectedUsdCost = toUsdReferencePrice(sourceLbpCost, 'LBP', storeProfile);
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
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _customers.length; index++) {
      final item = _customers[index];
      _customers[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _sales.length; index++) {
      final item = _sales[index];
      _sales[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? item.date : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
      );
    }
    for (var index = 0; index < _suppliers.length; index++) {
      final item = _suppliers[index];
      _suppliers[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
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
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? item.date : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
      );
    }
  }

  CatalogItem _prepareCatalogItemForSync(CatalogItem item, DateTime now) {
    return item.copyWith(
      createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
      updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
      deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
      syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
        storeId: item.storeId.isEmpty ? appIdentity.storeId : item.storeId,
        branchId: item.branchId.isEmpty ? appIdentity.branchId : item.branchId,
        version: item.version <= 0 ? 1 : item.version,
        lastModifiedByDeviceId: item.lastModifiedByDeviceId.isEmpty ? (item.deviceId.isEmpty ? _deviceId : item.deviceId) : item.lastModifiedByDeviceId,
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
        final parsed = AppIdentity.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        final token = parsed.deviceToken.trim().isNotEmpty
            ? parsed.deviceToken.trim()
            : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}';
        final normalized = parsed.copyWith(
          deviceId: _deviceId,
          platform: _detectPlatform(),
          deviceToken: token,
          deviceName: parsed.deviceName.trim().isNotEmpty ? parsed.deviceName.trim() : _deviceId,
        );
        unawaited(LocalDatabaseService.setString(_appIdentityKey, jsonEncode(normalized.toJson())));
        return normalized;
      } catch (_) {}
    }
    final created = AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform(), detectedDeviceName: _detectInitialDeviceName());
    unawaited(LocalDatabaseService.setString(_appIdentityKey, jsonEncode(created.toJson())));
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
    final normalized = _normalizedLocalIdentity(current.copyWith(deviceName: cleanName));
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(normalized.toJson()));
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
    required String recoveryKey,
    String? branchId,
    String? hostDeviceId,
    String? deviceToken,
    String? cloudTenantId,
    DeviceRole? deviceRole,
    SyncMode? syncMode,
  }) async {
    final cleanStoreId = storeId.trim().toUpperCase();
    final cleanRecoveryKey = recoveryKey.trim().toUpperCase();
    if (!cleanStoreId.startsWith('ST-') || cleanRecoveryKey.isEmpty) {
      throw ArgumentError('A valid Store ID and Recovery Key are required.');
    }
    final cleanBranchId = (branchId == null || branchId.trim().isEmpty) ? appIdentity.branchId : branchId.trim().toUpperCase();
    final nextRole = deviceRole ?? appIdentity.deviceRole;
    final recoveredIdentity = appIdentity.copyWith(
      storeId: cleanStoreId,
      branchId: cleanBranchId,
      recoveryKey: cleanRecoveryKey,
      hostDeviceId: hostDeviceId ?? (nextRole == DeviceRole.host ? _deviceId : appIdentity.hostDeviceId),
      deviceToken: (deviceToken == null || deviceToken.trim().isEmpty) ? appIdentity.deviceToken : deviceToken.trim(),
      cloudTenantId: (cloudTenantId == null || cloudTenantId.trim().isEmpty) ? appIdentity.cloudTenantId : cloudTenantId.trim(),
      deviceRole: nextRole,
      syncMode: syncMode ?? appIdentity.syncMode,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      updatedAt: DateTime.now(),
    );
    _assertLanCloudRoleRules(recoveredIdentity, source: 'store recovery');
    _appIdentity = recoveredIdentity;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    notifyListeners();
  }

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) {
    final local = appIdentity;
    if (local.isHost) return local.copyWith(deviceId: _deviceId, platform: _detectPlatform(), updatedAt: DateTime.now());
    if (decoded['appIdentity'] is! Map) return local.copyWith(deviceId: _deviceId, platform: _detectPlatform());
    final remote = AppIdentity.fromJson(Map<String, dynamic>.from(decoded['appIdentity'] as Map));
    return local.copyWith(
      storeId: remote.storeId.isNotEmpty ? remote.storeId : local.storeId,
      branchId: remote.branchId.isNotEmpty ? remote.branchId : local.branchId,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      deviceRole: DeviceRole.client,
      appRole: remote.appRole,
      syncMode: local.syncMode == SyncMode.localOnly ? SyncMode.lanOnly : local.syncMode,
      hostDeviceId: remote.deviceId.isNotEmpty ? remote.deviceId : local.hostDeviceId,
      cloudTenantId: remote.cloudTenantId.isNotEmpty ? remote.cloudTenantId : local.cloudTenantId,
      deviceToken: local.deviceToken.trim().isNotEmpty ? local.deviceToken : 'device_${DateTime.now().microsecondsSinceEpoch}_${_deviceId.hashCode.abs()}',
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
    final approvedDeviceId = LocalDatabaseService.getString(_hostTransferApprovedDeviceKey)?.trim() ?? '';
    return approvedDeviceId.isNotEmpty && approvedDeviceId == _deviceId;
  }

  String get approvedHostTransferDeviceId => LocalDatabaseService.getString(_hostTransferApprovedDeviceKey)?.trim() ?? '';

  Map<String, dynamic>? get pendingHostTransferRequest {
    final raw = LocalDatabaseService.getString(_hostTransferRequestKey)?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? get latestHostTransferNotification {
    final raw = LocalDatabaseService.getString(_hostTransferNotificationKey)?.trim() ?? '';
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

  Future<void> _storeHostTransferNotification(Map<String, dynamic> payload) async {
    await LocalDatabaseService.setString(_hostTransferNotificationKey, jsonEncode(payload));
  }

  Future<void> clearLocalHostTransferRequest() async {
    await LocalDatabaseService.setString(_hostTransferRequestKey, '');
    notifyListeners();
  }

  Future<void> _forceApplyRoleFromTransfer(AppIdentity next) async {
    final normalized = _normalizedLocalIdentity(next);
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(normalized.toJson()));
  }

  void _assertSafeRoleTransition(AppIdentity next, {required String source, bool allowApprovedTransfer = false, bool allowInitialHostRegistration = false}) {
    final current = _appIdentity;
    if (current == null) return;
    if (current.deviceRole == next.deviceRole) return;

    // Fix #4: backup, restore, pairing, rebuild, and snapshot import flows must
    // never silently convert a Host into a Client. Host role changes are only
    // allowed through the official Transfer Host flow.
    if (current.isHost && next.isClient) {
      throw StateError('Host devices cannot be converted to Clients by $source. Use Transfer Host instead.');
    }

    // A Client can become Host only after an explicit Host transfer approval.
    if (current.isClient && next.isHost &&
        !allowInitialHostRegistration &&
        !(allowApprovedTransfer && _isApprovedHostTransferTarget())) {
      throw StateError('Client devices cannot become Host by $source. Request and approve Transfer Host first.');
    }
  }

  void _assertLanCloudRoleRules(AppIdentity next, {required String source}) {
    final platform = next.platform == AppPlatformType.unknown ? _detectPlatform() : next.platform;

    // Fix #9: Web devices must never be authoritative Hosts because browsers
    // cannot reliably run the local Host API/server and should not own Host
    // authority for Cloud either.
    if (platform == AppPlatformType.web && next.isHost) {
      throw StateError('Web devices cannot operate as Host. Use a desktop or native mobile Host device.');
    }

    final lanHost = _isLanHostConfigured;
    final lanClient = _isLanClientConfigured;
    final cloudHost = next.isHost && (next.syncMode == SyncMode.cloudConnected || next.syncMode == SyncMode.marketplaceEnabled);
    final cloudClient = next.isClient && (next.syncMode == SyncMode.cloudConnected || next.syncMode == SyncMode.marketplaceEnabled);
    final lanIdentityClient = next.isClient && next.syncMode == SyncMode.lanOnly;

    // A Host may be LAN Host, Cloud Host, or both. It must not simultaneously
    // carry LAN Client state from an old pairing.
    if (next.isHost && lanClient) {
      throw StateError('A Host device cannot keep LAN Client state. Clear local data or use Transfer Host before changing sync role.');
    }

    // A Client may configure both LAN and Cloud transport settings, but only
    // one active transport may run at a time. Sync progress is tracked by
    // deviceId/storeId/branchId, not by the transport that delivered it.
    if (next.isClient && lanClient && cloudClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'cloud') {
        throw StateError('Client has LAN and Cloud configured but no active sync transport was selected.');
      }
    }
    if (lanIdentityClient && cloudClient) {
      final active = next.activeSyncTransportNormalized;
      if (active != 'lan' && active != 'cloud') {
        throw StateError('Client has LAN and Cloud configured but no active sync transport was selected.');
      }
    }

    // Prevent cross-authority conflicts: Host in one system, Client in another.
    if (lanHost && cloudClient) {
      throw StateError('LAN Host + Cloud Client is not allowed by $source. Host devices cannot be Clients in another sync system.');
    }
    if (cloudHost && lanClient) {
      throw StateError('Cloud Host + LAN Client is not allowed by $source. Host devices cannot be Clients in another sync system.');
    }
  }


  Future<void> updateAppIdentityDuringSetup(AppIdentity identity) async {
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: 'setup/pairing/rebuild');
    _assertLanCloudRoleRules(normalized, source: 'setup/pairing/rebuild');
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(normalized.toJson()));
    await SyncDeviceStateStore.setActiveTransport(normalized, normalized.activeSyncTransportNormalized);
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
    await SyncDeviceStateStore.setActiveTransport(normalized, normalized.activeSyncTransportNormalized);
    notifyListeners();
  }

  Future<void> updateAppIdentityLocalOnly(AppIdentity identity, {String source = 'local sync settings'}) async {
    requirePermission(AppPermission.settingsManage);
    final normalized = _normalizedLocalIdentity(identity);
    _assertSafeRoleTransition(normalized, source: source);
    _assertLanCloudRoleRules(normalized, source: source);
    final previousJson = jsonEncode(appIdentity.toJson());
    final nextJson = jsonEncode(normalized.toJson());
    if (previousJson == nextJson) return;
    _appIdentity = normalized;
    await LocalDatabaseService.setString(_appIdentityKey, nextJson);
    await SyncDeviceStateStore.setActiveTransport(normalized, normalized.activeSyncTransportNormalized);
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
      throw StateError('Only Client devices switch the active sync transport. Hosts may run LAN and Cloud together.');
    }
    if (normalizedTransport == 'lan' && !_isLanClientConfigured) {
      throw StateError('LAN is configured only when this device has a saved Client pairing. Configure LAN before switching to it.');
    }
    if (normalizedTransport == 'cloud' && !_isCloudClientConfigured) {
      throw StateError('Cloud is configured only when this device has saved Cloud credentials. Configure Cloud before switching to it.');
    }

    final nextIdentity = identity.copyWith(
      syncMode: normalizedTransport == 'lan' ? SyncMode.lanOnly : SyncMode.cloudConnected,
      activeSyncTransport: normalizedTransport,
      updatedAt: DateTime.now(),
    );
    _assertLanCloudRoleRules(nextIdentity, source: 'active transport switch');
    _appIdentity = nextIdentity;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(nextIdentity.toJson()));
    await SyncDeviceStateStore.setActiveTransport(nextIdentity, normalizedTransport);
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
    await LocalDatabaseService.setString(_hostTransferRequestKey, jsonEncode(payload));
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
    await LocalDatabaseService.setString(_hostTransferApprovedDeviceKey, cleanDeviceId);
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
      payload: {
        ...transferPayload,
        'status': 'approved_pending_activation',
      },
    );

    // The current Host must remain authoritative after approval. The device
    // requesting the transfer becomes Host only after explicit activation, then
    // publishes HOST_CHANGED. This prevents any period with no Host.
    await LocalDatabaseService.setString(_hostTransferRequestKey, jsonEncode({
      ...transferPayload,
      'requestingDeviceId': cleanDeviceId,
      'status': 'approved_pending_activation',
    }));
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> activateApprovedHostTransfer() async {
    if (!appIdentity.isClient) {
      throw StateError('Only a Client device can activate an approved Host transfer.');
    }
    if (!_isApprovedHostTransferTarget()) {
      throw StateError('No approved Host transfer was found for this device.');
    }
    final oldHostDeviceId = appIdentity.hostDeviceId;
    final next = _normalizedLocalIdentity(appIdentity.copyWith(
      deviceRole: DeviceRole.host,
      hostDeviceId: '',
      updatedAt: DateTime.now(),
    ));
    _assertSafeRoleTransition(next, source: 'approved Host transfer', allowApprovedTransfer: true);
    _assertLanCloudRoleRules(next, source: 'approved Host transfer');
    _appIdentity = next;
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(next.toJson()));
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
    return decoded.map((item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  List<AppUser> _loadUsers() {
    final raw = LocalDatabaseService.getString(_usersKey);
    if (raw == null || raw.isEmpty) return <AppUser>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map))).toList();
  }

  Future<void> _saveRolesAndUsers() async {
    await LocalDatabaseService.setString(_rolesKey, jsonEncode(_roles.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_usersKey, jsonEncode(_users.map((item) => item.toJson()).toList()));
  }

  Future<void> _ensureDefaultAdminUser() async {
    final now = DateTime.now();
    final existingAdminRole = _roles.indexWhere((role) => role.id == 'admin');
    if (existingAdminRole == -1) {
      _roles.add(UserRole(id: 'admin', name: 'Admin', permissions: Set<String>.from(AppPermission.all), isSystem: true, createdAt: now, updatedAt: now));
    } else {
      _roles[existingAdminRole] = _roles[existingAdminRole].copyWith(name: 'Admin', permissions: Set<String>.from(AppPermission.all), isSystem: true, updatedAt: now);
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

  Future<bool> login(String username, String password, {bool remember = false}) async {
    if (isSuspendedByHost) return false;
    final normalized = username.trim().toLowerCase();
    final activeMatches = _users.where((user) => user.username.trim().toLowerCase() == normalized && user.isActive).toList();
    if (activeMatches.length > 1) {
      // Security conflict: never guess which duplicated username should log in.
      return false;
    }
    for (var index = 0; index < _users.length; index++) {
      final user = _users[index];
      if (user.username.trim().toLowerCase() != normalized || !user.isActive) continue;
      if (!await _verifyPasswordAsync(password, user.passwordHash)) return false;
      final updated = user.copyWith(lastLoginAt: DateTime.now());
      _users[index] = updated;
      _activeUser = updated;
      _rememberLogin = remember;
      notifyListeners();
      unawaited(LocalDatabaseService.setString(_rememberLoginKey, remember ? 'true' : 'false'));
      unawaited(LocalDatabaseService.setString(_activeUserKey, remember ? updated.id : ''));
      unawaited(_saveRolesAndUsers());
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.setString(_activeUserKey, '');
    await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    notifyListeners();
  }



  Future<bool> verifyAdminPassword(String password) async {
    final user = _activeUser;
    if (user == null || !isAdmin) return false;
    return _verifyPasswordAsync(password, user.passwordHash);
  }

  Future<bool> _verifyPasswordAsync(String password, String storedHash) async {
    if (storedHash.startsWith(_passwordHashPrefix)) {
      return compute(_verifyPasswordInBackground, <String, String>{'password': password.trim(), 'storedHash': storedHash});
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
      return storedHash == _hashPasswordWithSalt(cleaned, parts[2], iterations: iterations);
    }

    // Backward compatibility for accounts created before the password hash
    // upgrade. Password changes and first-run setup now write PBKDF2 hashes.
    if (storedHash.startsWith(_legacyLocalCredentialHashPrefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 3) return false;
      return storedHash == _hashLegacyLocalCredentialWithSalt(cleaned, parts[1]);
    }
    return false;
  }

  Future<void> addOrUpdateRole(UserRole role) async {
    requirePermission(AppPermission.rolesManage);
    if (role.name.trim().isEmpty) throw ArgumentError('Role name is required.');
    if (role.id == 'admin') throw StateError('The built-in Admin role cannot be edited.');
    final now = DateTime.now();
    final id = role.id.trim().isEmpty ? 'role_${now.microsecondsSinceEpoch}' : role.id;
    final saved = UserRole(id: id, name: role.name.trim(), permissions: role.permissions.intersection(Set<String>.from(AppPermission.all)), isSystem: false, createdAt: role.createdAt ?? now, updatedAt: now);
    final index = _roles.indexWhere((item) => item.id == id);
    if (index == -1) {
      _roles.add(saved);
    } else {
      if (_roles[index].isSystem) throw StateError('System roles cannot be edited.');
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
    if (_users.any((user) => user.roleId == id)) throw StateError('Move users to another role before deleting this role.');
    final removed = _roles.firstWhere((role) => role.id == id && !role.isSystem);
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

  Future<void> addOrUpdateUser(AppUser user, {String? password}) async {
    requirePermission(AppPermission.usersManage);
    if (user.fullName.trim().isEmpty || user.username.trim().isEmpty) throw ArgumentError('Name and username are required.');
    if (roleById(user.roleId) == null) throw ArgumentError('Role not found.');
    final normalizedUsername = user.username.trim().toLowerCase();
    final duplicate = _users.any((item) => item.id != user.id && item.username.trim().toLowerCase() == normalizedUsername);
    if (duplicate) throw ArgumentError('Username already exists.');
    final now = DateTime.now();
    final isCreate = user.id.trim().isEmpty || _users.indexWhere((item) => item.id == user.id) == -1;
    if (isCreate && (password == null || password.trim().length < 4)) throw ArgumentError('Password must be at least 4 characters.');
    final id = isCreate ? 'user_${now.microsecondsSinceEpoch}' : user.id;
    final saved = AppUser(
      id: id,
      fullName: user.fullName.trim(),
      username: normalizedUsername,
      passwordHash: password != null && password.trim().isNotEmpty ? _hashPassword(password.trim()) : user.passwordHash,
      roleId: user.roleId,
      extraPermissions: user.extraPermissions.intersection(Set<String>.from(AppPermission.all)),
      deniedPermissions: user.deniedPermissions.intersection(Set<String>.from(AppPermission.all)),
      isActive: user.isActive,
      isSystem: user.isSystem,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
      lastLoginAt: user.lastLoginAt,
    );
    final index = _users.indexWhere((item) => item.id == id);
    if (index == -1) {
      _users.add(saved);
    } else {
      if (_users[index].isSystem && saved.roleId != 'admin') throw StateError('The built-in admin user must keep the Admin role.');
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
    final adminCount = _users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) throw StateError('Create another active admin before deleting this user.');
    if (user.isSystem) throw StateError('The built-in admin user cannot be deleted.');
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

  String _hashPassword(String password) {
    final salt = _generateSalt();
    return _hashPasswordWithSalt(password, salt, iterations: _passwordHashIterations);
  }

  String _hashPasswordWithSalt(String password, String salt, {required int iterations}) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(Uint8List.fromList(utf8.encode('ventio|password|$password')));
    return '$_passwordHashPrefix$iterations:$salt:${base64UrlEncode(hash)}';
  }

  String _hashLegacyLocalCredentialWithSalt(String password, String salt) {
    const legacyPurpose = 'store_manager_pro|local_' 'p' 'in_v2';
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
    return StoreProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
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
      final isWalkIn = customer.id == walkInCustomerId || normalizedName == walkInCustomerName.toLowerCase();

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
  }

  String resolveCustomerName(String? customerId) {
    if (customerId == null || customerId.isEmpty || customerId == walkInCustomerId) {
      return walkInCustomerName;
    }

    for (final customer in _customers) {
      if (customer.id == customerId) return customer.name;
    }

    return walkInCustomerName;
  }

  String sanitizeSelectedCustomerId(String? customerId) {
    final normalized = customerId?.trim();
    if (normalized == null || normalized.isEmpty) return walkInCustomerId;
    final exists = _customers.any((customer) => customer.id == normalized);
    return exists ? normalized : walkInCustomerId;
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
      if (earliest == 0 || change.sequence < earliest) earliest = change.sequence;
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

  int _minimumActivePeerAckSequence({Duration activeWindow = const Duration(days: 14)}) {
    if (!appIdentity.isHost) return _latestStoredAuthoritativeSequence();
    final now = DateTime.now();
    final activePeers = SyncDeviceStateStore.loadPeerStates().where((peer) {
      final seen = peer.lastSeenAt ?? peer.updatedAt;
      if (seen == null) return false;
      return now.difference(seen) <= activeWindow;
    }).toList();
    if (activePeers.isEmpty) return 0;
    return activePeers.fold<int>(1 << 62, (minSeq, peer) {
      final seq = peer.lastAckSequence > 0 ? peer.lastAckSequence : peer.lastAppliedSequence;
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
    // while Hive/legacy storage still receives the compact sync-only JSON.
    await Future.wait([
      LocalDatabaseService.setString(_syncChangesKey, jsonEncode(_syncChanges.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_syncQueueKey, jsonEncode(_syncQueue.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_syncSequenceKey, _syncSequence.toString()),
    ]);
  }

  Future<void> _saveAll() async {
    _normalizeCustomers();
    _replaceUsersWithoutDuplicates(List<AppUser>.from(_users));
    _compactSyncedHistory();
    await Future.wait([
      LocalDatabaseService.setString(_productsKey, jsonEncode(_products.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_customersKey, jsonEncode(_customers.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_salesKey, jsonEncode(_sales.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_saleQuotationsKey, jsonEncode(_saleQuotations.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_deliveryNotesKey, jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_billsOfMaterialsKey, jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_manufacturingOrdersKey, jsonEncode(_manufacturingOrders.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_suppliersKey, jsonEncode(_suppliers.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_supplierProductPricesKey, jsonEncode(_supplierProductPrices.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_categoriesKey, jsonEncode(_categories.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_brandsKey, jsonEncode(_brands.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_unitsKey, jsonEncode(_units.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_expensesKey, jsonEncode(_expenses.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_purchasesKey, jsonEncode(_purchases.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_stockMovementsKey, jsonEncode(_stockMovements.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_warehousesKey, jsonEncode(_warehouses.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_accountTransactionsKey, jsonEncode(_accountTransactions.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_syncChangesKey, jsonEncode(_syncChanges.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_syncQueueKey, jsonEncode(_syncQueue.map((item) => item.toJson()).toList())),
      LocalDatabaseService.setString(_deviceIdKey, _deviceId),
      LocalDatabaseService.setString(_storeProfileKey, jsonEncode(_storeProfile.toJson())),
      LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString()),
      LocalDatabaseService.setString(_purchaseCounterKey, _purchaseCounter.toString()),
      LocalDatabaseService.setString(_syncSequenceKey, _syncSequence.toString()),
      LocalDatabaseService.setString(_schemaVersionKey, '17'),
    ]);
  }

  Future<void> _saveDirty({
    bool products = false,
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
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    if (LocalDatabaseService.isSqliteAuthoritative) {
      await _saveDirtySqliteHotPath(
        products: products,
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
        warehouses: warehouses,
        accountTransactions: accountTransactions,
        storeProfile: storeProfile,
        invoiceCounter: invoiceCounter,
        purchaseCounter: purchaseCounter,
        sync: sync,
      );
      return;
    }

    final writes = <Future<void>>[];
    if (customers) _normalizeCustomers();
    if (sync) _compactSyncedHistory();
    if (products) writes.add(LocalDatabaseService.setString(_productsKey, jsonEncode(_products.map((item) => item.toJson()).toList())));
    if (customers) writes.add(LocalDatabaseService.setString(_customersKey, jsonEncode(_customers.map((item) => item.toJson()).toList())));
    if (sales) writes.add(LocalDatabaseService.setString(_salesKey, jsonEncode(_sales.map((item) => item.toJson()).toList())));
    if (saleQuotations) writes.add(LocalDatabaseService.setString(_saleQuotationsKey, jsonEncode(_saleQuotations.map((item) => item.toJson()).toList())));
    if (deliveryNotes) writes.add(LocalDatabaseService.setString(_deliveryNotesKey, jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList())));
    if (billsOfMaterials) writes.add(LocalDatabaseService.setString(_billsOfMaterialsKey, jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList())));
    if (manufacturingOrders) writes.add(LocalDatabaseService.setString(_manufacturingOrdersKey, jsonEncode(_manufacturingOrders.map((item) => item.toJson()).toList())));
    if (suppliers) writes.add(LocalDatabaseService.setString(_suppliersKey, jsonEncode(_suppliers.map((item) => item.toJson()).toList())));
    if (supplierProductPrices) writes.add(LocalDatabaseService.setString(_supplierProductPricesKey, jsonEncode(_supplierProductPrices.map((item) => item.toJson()).toList())));
    if (categories) writes.add(LocalDatabaseService.setString(_categoriesKey, jsonEncode(_categories.map((item) => item.toJson()).toList())));
    if (brands) writes.add(LocalDatabaseService.setString(_brandsKey, jsonEncode(_brands.map((item) => item.toJson()).toList())));
    if (units) writes.add(LocalDatabaseService.setString(_unitsKey, jsonEncode(_units.map((item) => item.toJson()).toList())));
    if (expenses) writes.add(LocalDatabaseService.setString(_expensesKey, jsonEncode(_expenses.map((item) => item.toJson()).toList())));
    if (purchases) writes.add(LocalDatabaseService.setString(_purchasesKey, jsonEncode(_purchases.map((item) => item.toJson()).toList())));
    if (stockMovements) writes.add(LocalDatabaseService.setString(_stockMovementsKey, jsonEncode(_stockMovements.map((item) => item.toJson()).toList())));
    if (warehouses) writes.add(LocalDatabaseService.setString(_warehousesKey, jsonEncode(_warehouses.map((item) => item.toJson()).toList())));
    if (accountTransactions) writes.add(LocalDatabaseService.setString(_accountTransactionsKey, jsonEncode(_accountTransactions.map((item) => item.toJson()).toList())));
    if (storeProfile) writes.add(LocalDatabaseService.setString(_storeProfileKey, jsonEncode(_storeProfile.toJson())));
    if (invoiceCounter) writes.add(LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString()));
    if (purchaseCounter) writes.add(LocalDatabaseService.setString(_purchaseCounterKey, _purchaseCounter.toString()));
    if (sync) {
      writes
        ..add(LocalDatabaseService.setString(_syncChangesKey, jsonEncode(_syncChanges.map((item) => item.toJson()).toList())))
        ..add(LocalDatabaseService.setString(_syncQueueKey, jsonEncode(_syncQueue.map((item) => item.toJson()).toList())))
        ..add(LocalDatabaseService.setString(_syncSequenceKey, _syncSequence.toString()));
    }
    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

  Future<void> _saveDirtySqliteHotPath({
    bool products = false,
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
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    if (customers) _normalizeCustomers();

    final writes = <Future<void>>[];

    Future<void> persistRows(String key) async {
      final rows = _sqliteDirtyBusinessRows.remove(key);
      if (rows == null || rows.isEmpty) return;
      for (final payload in rows.values) {
        await LocalDatabaseService.upsertBusinessEntityJson(key, payload);
      }
    }

    if (products) writes.add(persistRows(_productsKey));
    if (customers) writes.add(persistRows(_customersKey));
    if (sales) writes.add(persistRows(_salesKey));
    if (saleQuotations) {
      _sqliteDirtyBusinessRows.remove(_saleQuotationsKey);
      writes.add(LocalDatabaseService.setString(_saleQuotationsKey, jsonEncode(_saleQuotations.map((item) => item.toJson()).toList())));
    }
    if (deliveryNotes) {
      _sqliteDirtyBusinessRows.remove(_deliveryNotesKey);
      writes.add(LocalDatabaseService.setString(_deliveryNotesKey, jsonEncode(_deliveryNotes.map((item) => item.toJson()).toList())));
    }
    if (billsOfMaterials) {
      _sqliteDirtyBusinessRows.remove(_billsOfMaterialsKey);
      writes.add(LocalDatabaseService.setString(_billsOfMaterialsKey, jsonEncode(_billsOfMaterials.map((item) => item.toJson()).toList())));
    }
    if (manufacturingOrders) {
      _sqliteDirtyBusinessRows.remove(_manufacturingOrdersKey);
      writes.add(LocalDatabaseService.setString(_manufacturingOrdersKey, jsonEncode(_manufacturingOrders.map((item) => item.toJson()).toList())));
    }
    if (suppliers) writes.add(persistRows(_suppliersKey));
    if (supplierProductPrices) writes.add(persistRows(_supplierProductPricesKey));
    if (categories) writes.add(persistRows(_categoriesKey));
    if (brands) writes.add(persistRows(_brandsKey));
    if (units) writes.add(persistRows(_unitsKey));
    if (expenses) writes.add(persistRows(_expensesKey));
    if (purchases) writes.add(persistRows(_purchasesKey));
    if (stockMovements) writes.add(persistRows(_stockMovementsKey));
    if (warehouses) writes.add(LocalDatabaseService.setString(_warehousesKey, jsonEncode(_warehouses.map((item) => item.toJson()).toList())));
    if (accountTransactions) writes.add(persistRows(_accountTransactionsKey));

    if (storeProfile) writes.add(LocalDatabaseService.setString(_storeProfileKey, jsonEncode(_storeProfile.toJson())));
    if (invoiceCounter) writes.add(LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString()));
    if (purchaseCounter) writes.add(LocalDatabaseService.setString(_purchaseCounterKey, _purchaseCounter.toString()));

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
      writes.add(LocalDatabaseService.setString(_syncSequenceKey, _syncSequence.toString()));
    }

    if (writes.isEmpty) return;
    await Future.wait(writes);
  }


  Product? _findProductById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Product? findProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    final matches = _products
        .where((product) => !product.isDeleted)
        .where((product) =>
            product.code.trim().toLowerCase() == normalized ||
            product.effectiveSaleUnits.any((unit) => unit.barcode.trim().isNotEmpty && unit.barcode.trim().toLowerCase() == normalized))
        .toList();
    if (matches.length != 1) return null;
    return matches.first;
  }


  void _resetBusinessDataInMemory({bool keepStoreProfile = true}) {
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
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    if (!keepStoreProfile) {
      _storeProfile = StoreProfile.defaults;
    }
  }

  Future<void> resetBusinessData({bool keepStoreProfile = true}) async {
    requirePermission(AppPermission.backupRestore);

    // Local-only reset. This must never create a SyncChange or propagate delete
    // operations to Clients. Host factory reset is handled by factoryResetLocalDevice().
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    await _saveAll();
    notifyListeners();
  }

  Future<void> clearLocalDeviceBusinessData({bool keepStoreProfile = true}) async {
    // Client-only maintenance operation. This must never create a SyncChange or
    // deletion event because the Host remains the source of truth. It also
    // clears pull cursors so the next sync can rebuild from a full Host
    // snapshot instead of resuming after stale local leftovers.
    final identity = appIdentity;
    _syncChanges.clear();
    _syncQueue.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    final lanRaw = LocalDatabaseService.getString('lan_sync_settings_v2');
    if (lanRaw != null && lanRaw.trim().isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(lanRaw) as Map);
        decoded.remove('lastPullCursor');
        decoded['lastSyncAt'] = null;
        await LocalDatabaseService.setString('lan_sync_settings_v2', jsonEncode(decoded));
      } catch (_) {
        // Keep the data clear even if old LAN settings are malformed.
      }
    }
    _appIdentity = identity.copyWith(deviceId: _deviceId, platform: _detectPlatform());
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    await _saveAll();
    notifyListeners();
  }


  Future<int> clearLocalOnlyPendingSyncChanges() async {
    requirePermission(AppPermission.settingsManage);
    final invalidChangeIds = _syncChanges
        .where((change) =>
            !change.isSynced &&
            change.entityType == 'app_identity' &&
            change.operation == 'update')
        .map((change) => change.id)
        .toSet();
    if (invalidChangeIds.isEmpty) return 0;

    final beforeQueue = _syncQueue.length;
    _syncQueue.removeWhere((item) => invalidChangeIds.contains(item.changeId) && !item.isSynced);
    final removedQueueRows = beforeQueue - _syncQueue.length;

    final queuedInvalidIds = _syncQueue.map((item) => item.changeId).toSet();
    _syncChanges.removeWhere((change) => invalidChangeIds.contains(change.id) && !queuedInvalidIds.contains(change.id));

    await _saveSyncStateOnly();
    notifyListeners();
    return removedQueueRows;
  }

  Future<void> factoryResetLocalDevice({bool preserveAdminUsers = false}) async {
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
    _categories.clear();
    _brands.clear();
    _units.clear();
    _syncChanges.clear();
    _syncQueue.clear();
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _storeProfile = StoreProfile.defaults;
    _activeUser = null;
    _rememberLogin = false;
    if (!preserveAdminUsers) {
      _users.clear();
      _roles.clear();
      await _ensureDefaultAdminUser();
    }
    _deviceId = _generatePrefixedId('DV');
    _appIdentity = AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform()).copyWith(deviceRole: DeviceRole.standalone, syncMode: SyncMode.localOnly);
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    await LocalDatabaseService.setString(_activeUserKey, '');
    await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    await LocalDatabaseService.deleteString('lan_sync_settings_v2');
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
    return _syncChanges.any((change) =>
        pendingChangeIds.contains(change.id) &&
        change.entityType == entityType &&
        change.entityId == entityId);
  }

  Future<int> cleanupSoftDeletedRecords({Duration retention = const Duration(days: 30)}) async {
    final cutoff = DateTime.now().subtract(retention);
    var removed = 0;

    bool expired(DateTime? deletedAt) => deletedAt != null && deletedAt.isBefore(cutoff);

    final beforeProducts = _products.length;
    _products.removeWhere((item) =>
        expired(item.deletedAt) &&
        !_hasPendingSyncFor('product', item.id) &&
        !isProductReferenced(item.id));
    removed += beforeProducts - _products.length;

    final beforeCustomers = _customers.length;
    _customers.removeWhere((item) => expired(item.deletedAt) && item.id != 'walk_in' && !_hasPendingSyncFor('customer', item.id));
    removed += beforeCustomers - _customers.length;

    final beforeSuppliers = _suppliers.length;
    _suppliers.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('supplier', item.id));
    removed += beforeSuppliers - _suppliers.length;

    final beforeSupplierProductPrices = _supplierProductPrices.length;
    _supplierProductPrices.removeWhere((item) =>
        expired(item.deletedAt) && !_hasPendingSyncFor('supplier_product_price', item.id));
    removed += beforeSupplierProductPrices - _supplierProductPrices.length;

    final beforeExpenses = _expenses.length;
    _expenses.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('expense', item.id));
    removed += beforeExpenses - _expenses.length;

    final beforeCategories = _categories.length;
    _categories.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('category', item.id));
    removed += beforeCategories - _categories.length;

    final beforeBrands = _brands.length;
    _brands.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('brand', item.id));
    removed += beforeBrands - _brands.length;

    final beforeUnits = _units.length;
    _units.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('unit', item.id));
    removed += beforeUnits - _units.length;

    final beforeSales = _sales.length;
    _sales.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('sale', item.id));
    removed += beforeSales - _sales.length;

    final beforePurchases = _purchases.length;
    _purchases.removeWhere((item) => expired(item.deletedAt) && !_hasPendingSyncFor('purchase', item.id));
    removed += beforePurchases - _purchases.length;

    if (removed > 0) {
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return removed;
  }


  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() async {
    final problems = <String>[];
    final productIds = _products.where((item) => !item.isDeleted).map((item) => item.id).toSet();
    final supplierIds = _suppliers.where((item) => !item.isDeleted).map((item) => item.id).toSet();

    for (final price in _supplierProductPrices.where((item) => !item.isDeleted)) {
      if (!productIds.contains(price.productId)) {
        problems.add('Supplier price ${price.id} references missing product ${price.productId}');
      }
      if (!supplierIds.contains(price.supplierId)) {
        problems.add('Supplier price ${price.id} references missing supplier ${price.supplierId}');
      }
    }

    final activePriceKeys = <String>{};
    for (final price in _supplierProductPrices.where((item) => !item.isDeleted)) {
      final key = '${price.productId}::${price.supplierId}';
      if (!activePriceKeys.add(key)) {
        problems.add('Duplicate supplier price for product ${price.productId} and supplier ${price.supplierId}');
      }
    }

    for (final sale in _sales.where((item) => !item.isDeleted)) {
      if (sale.invoiceNo.trim().isEmpty) problems.add('Sale ${sale.id} has no invoice number');
      if (sale.items.isEmpty) problems.add('Sale ${sale.invoiceNo} has no line items');
      for (final item in sale.items) {
        if (!productIds.contains(item.productId)) {
          problems.add('Sale ${sale.invoiceNo} references missing product ${item.productId}');
        }
      }
      final movements = _stockMovements.where((movement) => movement.referenceId == sale.id && movement.type == 'sale').toList();
      if (sale.status != 'Cancelled' && movements.length < sale.items.length) {
        problems.add('Sale ${sale.invoiceNo} is missing stock movement(s)');
      }
    }

    for (final purchase in _purchases.where((item) => !item.isDeleted)) {
      if (purchase.items.isEmpty) problems.add('Purchase ${purchase.id} has no line items');
      for (final item in purchase.items) {
        if (!productIds.contains(item.productId)) {
          problems.add('Purchase ${purchase.id} references missing product ${item.productId}');
        }
      }
    }

    return BusinessDataIntegrityResult(
      ok: problems.isEmpty,
      message: problems.isEmpty ? 'Business data integrity check passed.' : problems.take(8).join('; '),
      problemCount: problems.length,
    );
  }

  Future<void> updateStoreProfile(StoreProfile profile) async {
    requirePermission(AppPermission.settingsManage);
    _storeProfile = profile;
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
    if (product.name.trim().isEmpty || product.code.trim().isEmpty || product.category.trim().isEmpty) {
      throw ArgumentError('Product name, code, and category are required.');
    }
    if (!product.price.isFinite || !product.cost.isFinite || product.price < 0 || product.cost < 0 || product.stock < 0 || product.lowStockThreshold < 0) {
      throw ArgumentError('Product price, cost, stock, and low stock threshold must be zero or positive.');
    }

    final normalizedCode = product.code.trim().toLowerCase();
    final normalizedBarcode = product.barcode.trim().toLowerCase();
    final previousCode = previousProduct?.code.trim().toLowerCase();
    final previousBarcode = previousProduct?.barcode.trim().toLowerCase();
    final codeChanged = previousProduct == null || normalizedCode != previousCode;
    final barcodeChanged = previousProduct == null || normalizedBarcode != previousBarcode;

    final duplicate = _products.any((item) {
      if (item.id == product.id || item.isDeleted) return false;
      final sameCode = codeChanged && item.code.trim().toLowerCase() == normalizedCode;
      final sameBarcode = barcodeChanged && normalizedBarcode.isNotEmpty && item.barcode.trim().toLowerCase() == normalizedBarcode;
      return sameCode || sameBarcode;
    });
    if (duplicate) {
      throw ArgumentError('Product code or barcode already exists.');
    }
  }


  String _generateUniqueProductCode({String? exceptProductId, Set<String>? reservedCodes}) {
    final activeProducts = _products.where((item) => !item.isDeleted).toList();
    final used = {
      ...activeProducts.where((item) => item.id != exceptProductId).map((item) => item.code.trim().toUpperCase()),
      ...?reservedCodes,
    };
    var counter = activeProducts.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }


  String get _invoiceDevicePrefix {
    final clean = _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
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

  void _rememberSqliteDirtyBusinessRow(String key, Map<String, dynamic> payload) {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    final id = payload['id']?.toString() ?? '';
    if (id.isEmpty) return;
    (_sqliteDirtyBusinessRows[key] ??= <String, Map<String, dynamic>>{})[id] = Map<String, dynamic>.from(payload);
  }

  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    final now = DateTime.now();
    final identity = appIdentity;
    final changeId = _newSyncEnvelopeId(now, identity.isHost ? 'evt' : 'cmd');

    // Sync V2 bridge:
    // The existing SyncChange envelope is still kept for compatibility with
    // tests, LAN endpoints, and old installations, but every new local change
    // is explicitly tagged as either a Client DraftCommand or a Host
    // AuthoritativeEvent. Cloud/LAN transports can therefore enforce the new
    // Host-authoritative contract without guessing from endpoint names.
    final mutationId = '${_deviceId}_${now.microsecondsSinceEpoch}_${entityType}_${entityId}_$operation';
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
      '_syncV2': syncV2Meta,
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
    final change = queued == null ? draftChange.copyWith(isSynced: true, syncedAt: now) : draftChange;
    _syncChanges.add(change);
    _sqliteDirtySyncChanges.add(change);
    final businessKey = _sqliteKeyForEntityType(entityType);
    if (businessKey != null) {
      _rememberSqliteDirtyBusinessRow(businessKey, payload);
    }
    if (queued != null) _sqliteDirtySyncQueue.add(queued);
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
      final identity = AppIdentity.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      final base = LocalDatabaseService.getString('cloud_api_base_url')?.trim() ?? '';
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
    final isLanClient = identity.isClient && activeTransport == 'lan' && _isLanClientConfigured;

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

  T _withSyncMeta<T>(T item, DateTime now, {bool isCreate = false, bool clearDeletedAt = true}) {
    final nextVersion = _readVersion(item) + (isCreate ? 0 : 1);
    final storeId = appIdentity.storeId;
    final branchId = appIdentity.branchId;
    if (item is Product) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_productsKey, updated.toJson());
      return updated as T;
    }
    if (item is Customer) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_customersKey, updated.toJson());
      return updated as T;
    }
    if (item is Supplier) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_suppliersKey, updated.toJson());
      return updated as T;
    }
    if (item is SupplierProductPrice) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_supplierProductPricesKey, updated.toJson());
      return updated as T;
    }
    if (item is Expense) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_expensesKey, updated.toJson());
      return updated as T;
    }
    if (item is CatalogItem) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      return updated as T;
    }
    if (item is Sale) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_salesKey, updated.toJson());
      return updated as T;
    }
    if (item is SaleQuotation) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId);
      _rememberSqliteDirtyBusinessRow(_saleQuotationsKey, updated.toJson());
      return updated as T;
    }
    if (item is DeliveryNote) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_deliveryNotesKey, updated.toJson());
      return updated as T;
    }
    if (item is BillOfMaterials) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_billsOfMaterialsKey, updated.toJson());
      return updated as T;
    }
    if (item is ManufacturingOrder) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_manufacturingOrdersKey, updated.toJson());
      return updated as T;
    }
    if (item is Purchase) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_purchasesKey, updated.toJson());
      return updated as T;
    }
    if (item is AccountTransaction) {
      final updated = item.copyWith(createdAt: isCreate ? now : item.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', storeId: storeId, branchId: branchId, version: nextVersion, lastModifiedByDeviceId: _deviceId, clearDeletedAt: clearDeletedAt);
      _rememberSqliteDirtyBusinessRow(_accountTransactionsKey, updated.toJson());
      return updated as T;
    }
    return item;
  }



  Future<void> addOrUpdateAccountTransaction(AccountTransaction transaction) async {
    requirePermission(AppPermission.reportsView);
    final now = DateTime.now();
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty ? 'USD' : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: transaction.debit < 0 ? 0 : transaction.debit,
      credit: transaction.credit < 0 ? 0 : transaction.credit,
    );
    if (normalized.accountType != 'customer' && normalized.accountType != 'supplier') {
      throw ArgumentError('Account transaction accountType must be customer or supplier.');
    }
    if (normalized.accountId.trim().isEmpty) {
      throw ArgumentError('Account transaction accountId is required.');
    }
    if (normalized.debit == 0 && normalized.credit == 0) {
      throw ArgumentError('Account transaction amount is required.');
    }
    final index = _accountTransactions.indexWhere((item) => item.id == normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(normalized, now, isCreate: index == -1);
    if (index == -1) {
      _accountTransactions.add(synced);
    } else {
      _accountTransactions[index] = synced;
    }
    _invalidateAccountLedgerCache();
    _recordSyncChange(entityType: 'account_transaction', entityId: synced.id, operation: index == -1 ? 'upsert' : 'update', payload: synced.toJson());
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteAccountTransaction(String id) async {
    requirePermission(AppPermission.reportsView);
    final index = _accountTransactions.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<AccountTransaction>(_accountTransactions[index].copyWith(deletedAt: now), now, clearDeletedAt: false);
    _accountTransactions[index] = deleted;
    _invalidateAccountLedgerCache();
    _recordSyncChange(entityType: 'account_transaction', entityId: id, operation: 'delete', payload: deleted.toJson());
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
  }


  void _upsertAccountTransactionInternal(AccountTransaction transaction, DateTime now, {String operation = 'upsert'}) {
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty ? 'USD' : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: transaction.debit < 0 ? 0 : transaction.debit,
      credit: transaction.credit < 0 ? 0 : transaction.credit,
    );
    if (normalized.accountType != 'customer' && normalized.accountType != 'supplier') return;
    if (normalized.accountId.trim().isEmpty) return;
    if (normalized.debit == 0 && normalized.credit == 0) return;
    final index = _accountTransactions.indexWhere((item) => item.id == normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(normalized, now, isCreate: index == -1);
    if (index == -1) {
      _accountTransactions.add(synced);
    } else {
      _accountTransactions[index] = synced;
    }
    _invalidateAccountLedgerCache();
    _recordSyncChange(entityType: 'account_transaction', entityId: synced.id, operation: operation, payload: synced.toJson());
  }

  void _recordPurchaseLedger(Purchase purchase, DateTime now) {
    if (!purchase.isReceived || purchase.isCancelled || purchase.supplierId.trim().isEmpty) return;
    final total = purchase.subtotal;
    final paid = purchase.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(AccountTransaction(
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
    ), now, operation: 'purchase_invoice');
    if (paid > 0) {
      _upsertAccountTransactionInternal(AccountTransaction(
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
      ), now, operation: 'purchase_payment');
    }
  }

  void _recordPurchaseCancelLedger(Purchase purchase, DateTime now, {String reason = '', bool isReturn = false}) {
    if (purchase.supplierId.trim().isEmpty) return;
    final total = purchase.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (total <= 0) return;
    final paid = purchase.paidAmount.clamp(0, total).toDouble();
    final note = reason.trim().isEmpty ? (isReturn ? 'Purchase return ${purchase.purchaseNo}' : 'Purchase cancelled') : reason.trim();
    _upsertAccountTransactionInternal(AccountTransaction(
      id: isReturn ? '${purchase.id}-purchase-return' : '${purchase.id}-purchase-cancel',
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
    ), now, operation: isReturn ? 'purchase_return' : 'purchase_cancel');
    if (paid > 0) {
      _upsertAccountTransactionInternal(AccountTransaction(
        id: isReturn ? '${purchase.id}-purchase-return-payment-reversal' : '${purchase.id}-purchase-payment-reversal',
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
        note: isReturn ? 'Refund/reversal of payment for returned purchase ${purchase.purchaseNo}' : 'Reversal of payment for cancelled purchase ${purchase.purchaseNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ), now, operation: isReturn ? 'purchase_return_payment_reversal' : 'purchase_payment_reversal');
    }
  }

  void _recordSaleLedger(Sale sale, DateTime now) {
    final accountId = sale.customerId.trim().isNotEmpty ? sale.customerId.trim() : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal;
    final paid = sale.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(AccountTransaction(
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
    ), now, operation: 'sale_invoice');
    if (paid > 0) {
      final cashPart = sale.paymentMethod == 'Cash' ? paid : sale.cashReceivedAmount.clamp(0, paid).toDouble();
      final nonCashPart = (paid - cashPart).clamp(0, paid).toDouble();
      if (cashPart > 0) {
        _upsertAccountTransactionInternal(AccountTransaction(
          id: nonCashPart > 0 ? '${sale.id}-sale-payment-cash' : '${sale.id}-sale-payment',
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
        ), now, operation: 'sale_payment_cash');
      }
      if (nonCashPart > 0) {
        _upsertAccountTransactionInternal(AccountTransaction(
          id: cashPart > 0 ? '${sale.id}-sale-payment-${sale.paymentMethod.toLowerCase()}' : '${sale.id}-sale-payment',
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
        ), now, operation: 'sale_payment');
      }
    }
  }

  void _recordSaleCancelLedger(Sale sale, DateTime now, {bool isReturn = false}) {
    final accountId = sale.customerId.trim().isNotEmpty ? sale.customerId.trim() : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal > 0 ? sale.invoiceTotal : ((sale.items.fold<double>(0, (sum, item) => sum + item.lineTotal) - sale.discount).clamp(0, double.infinity).toDouble());
    if (total <= 0) return;
    final paid = sale.paidAmount.clamp(0, total).toDouble();
    _upsertAccountTransactionInternal(AccountTransaction(
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
    ), now, operation: isReturn ? 'sale_return' : 'sale_cancel');
    if (paid > 0) {
      final cashPart = sale.paymentMethod == 'Cash' ? paid : sale.cashReceivedAmount.clamp(0, paid).toDouble();
      final nonCashPart = (paid - cashPart).clamp(0, paid).toDouble();
      if (cashPart > 0) {
        _upsertAccountTransactionInternal(AccountTransaction(
          id: isReturn
              ? (nonCashPart > 0 ? '${sale.id}-sale-return-payment-reversal-cash' : '${sale.id}-sale-return-payment-reversal')
              : (nonCashPart > 0 ? '${sale.id}-sale-payment-reversal-cash' : '${sale.id}-sale-payment-reversal'),
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
          note: isReturn ? 'Refund/reversal of cash payment for returned sale ${sale.invoiceNo}' : 'Reversal of cash payment for cancelled sale ${sale.invoiceNo}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ), now, operation: isReturn ? 'sale_return_payment_reversal_cash' : 'sale_payment_reversal_cash');
      }
      if (nonCashPart > 0) {
        _upsertAccountTransactionInternal(AccountTransaction(
          id: isReturn
              ? (cashPart > 0 ? '${sale.id}-sale-return-payment-reversal-${sale.paymentMethod.toLowerCase()}' : '${sale.id}-sale-return-payment-reversal')
              : (cashPart > 0 ? '${sale.id}-sale-payment-reversal-${sale.paymentMethod.toLowerCase()}' : '${sale.id}-sale-payment-reversal'),
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
          note: isReturn ? 'Refund/reversal of payment for returned sale ${sale.invoiceNo}' : 'Reversal of payment for cancelled sale ${sale.invoiceNo}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ), now, operation: isReturn ? 'sale_return_payment_reversal' : 'sale_payment_reversal');
      }
    }
  }

  Product _markProductForSync(Product product, DateTime now, {bool isCreate = false}) => _withSyncMeta<Product>(product, now, isCreate: isCreate);

  CatalogItem _markCatalogItemForSync(CatalogItem item, DateTime now, {bool isCreate = false}) => _withSyncMeta<CatalogItem>(item, now, isCreate: isCreate);


  Future<void> addOrUpdateProduct(Product product) async {
    final exists = _products.any((item) => item.id == product.id);
    requirePermission(exists ? AppPermission.productsEdit : AppPermission.productsCreate);
    final now = DateTime.now();
    final normalizedProduct = product.code.trim().isEmpty ? product.copyWith(code: _generateUniqueProductCode(exceptProductId: product.id)) : product;

    final index = _products.indexWhere((item) => item.id == normalizedProduct.id);
    final isCreate = index == -1;
    final previousProduct = isCreate ? null : _products[index];
    _validateProduct(normalizedProduct, previousProduct: previousProduct);
    final syncedProduct = _markProductForSync(normalizedProduct, now, isCreate: isCreate);
    if (isCreate) {
      _products.add(syncedProduct);
    } else {
      _products[index] = syncedProduct;
    }
    _recordSyncChange(
      entityType: 'product',
      entityId: syncedProduct.id,
      operation: isCreate ? 'create' : 'update',
      payload: syncedProduct.toJson(),
    );
    await _saveDirty(products: true, sync: true);
    notifyListeners();
  }

  bool isProductReferenced(String productId) {
    if (productId.trim().isEmpty) return false;
    final usedInSales = _sales.any((sale) =>
        !sale.isDeleted && sale.items.any((item) => item.productId == productId));
    if (usedInSales) return true;
    final usedInPurchases = _purchases.any((purchase) =>
        !purchase.isDeleted && purchase.items.any((item) => item.productId == productId));
    if (usedInPurchases) return true;
    return _stockMovements.any((movement) => movement.productId == productId);
  }

  Future<void> deleteProduct(String id) async {
    requirePermission(AppPermission.productsDelete);
    final index = _products.indexWhere((item) => item.id == id);
    if (index == -1) return;
    if (isProductReferenced(id)) {
      throw StateError('Cannot delete a product that is used by sales, purchases, or stock movements. Deactivate it instead.');
    }
    final now = DateTime.now();
    _products[index] = _withSyncMeta<Product>(_products[index].copyWith(deletedAt: now), now, clearDeletedAt: false);
    _recordSyncChange(entityType: 'product', entityId: id, operation: 'delete', payload: _products[index].toJson());
    final affectedPrices = _softDeleteSupplierProductPrices(
      productId: id,
      now: now,
      reason: 'Product deleted',
    );
    await _saveDirty(products: true, supplierProductPrices: affectedPrices > 0, sync: true);
    notifyListeners();
  }

  int _softDeleteSupplierProductPrices({String? productId, String? supplierId, required DateTime now, String reason = ''}) {
    var affected = 0;
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (item.isDeleted) continue;
      final matchesProduct = productId == null || item.productId == productId;
      final matchesSupplier = supplierId == null || item.supplierId == supplierId;
      if (!matchesProduct || !matchesSupplier) continue;
      final updated = _withSyncMeta<SupplierProductPrice>(
        item.copyWith(
          deletedAt: now,
          notes: reason.trim().isEmpty ? item.notes : [item.notes, reason].where((part) => part.trim().isNotEmpty).join(' — '),
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
    requirePermission(AppPermission.customersManage);
    if (customer.name.trim().isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final normalizedName = customer.name.trim();
    final activeDuplicate = _customers.any((item) =>
        !item.isDeleted &&
        item.id != customer.id &&
        item.id != walkInCustomerId &&
        item.name.trim().toLowerCase() == normalizedName.toLowerCase());
    if (activeDuplicate) {
      throw ArgumentError('Customer name already exists on this device. Sync duplicates will be reported as conflicts.');
    }
    final now = DateTime.now();
    final incoming = (customer.id == walkInCustomerId || normalizedName.toLowerCase() == walkInCustomerName.toLowerCase())
        ? _withSyncMeta<Customer>(walkInCustomer, now, isCreate: false)
        : _withSyncMeta<Customer>(customer.copyWith(name: normalizedName), now, isCreate: false);

    var index = _customers.indexWhere((item) => item.id == incoming.id);

    final isCreate = index == -1;
    final baseCustomer = isCreate ? incoming : incoming.copyWith(id: _customers[index].id, clearDeletedAt: true);
    final syncedCustomer = _withSyncMeta<Customer>(baseCustomer, now, isCreate: isCreate, clearDeletedAt: true);
    if (isCreate) {
      _customers.add(syncedCustomer);
    } else {
      _customers[index] = syncedCustomer;
    }
    _recordSyncChange(entityType: 'customer', entityId: syncedCustomer.id, operation: isCreate ? 'create' : 'update', payload: syncedCustomer.toJson());
    _normalizeCustomers();
    await _saveDirty(customers: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    requirePermission(AppPermission.customersManage);
    final index = _customers.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final customer = _customers[index];
    final isWalkIn = customer.id == walkInCustomerId || customer.name.trim().toLowerCase() == walkInCustomerName.toLowerCase();
    if (isWalkIn) return;
    final now = DateTime.now();
    _customers[index] = _withSyncMeta<Customer>(_customers[index].copyWith(deletedAt: now), now, clearDeletedAt: false);
    _recordSyncChange(entityType: 'customer', entityId: id, operation: 'delete', payload: _customers[index].toJson());
    _normalizeCustomers();
    await _saveDirty(customers: true, sync: true);
    notifyListeners();
  }

  Future<void> addOrUpdateSupplier(Supplier supplier) async {
    requirePermission(AppPermission.suppliersManage);
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final normalizedName = supplier.name.trim().toLowerCase();
    final duplicate = _suppliers.any((item) => !item.isDeleted && item.id != supplier.id && item.name.trim().toLowerCase() == normalizedName);
    if (duplicate) throw ArgumentError('Supplier name already exists on this device. Sync duplicates will be reported as conflicts.');
    final now = DateTime.now();
    final cleanedSupplier = supplier.copyWith(name: supplier.name.trim());
    final index = _suppliers.indexWhere((item) => item.id == cleanedSupplier.id);
    final isCreate = index == -1;
    final syncedSupplier = _withSyncMeta<Supplier>(cleanedSupplier, now, isCreate: isCreate);
    if (isCreate) {
      _suppliers.add(syncedSupplier);
    } else {
      _suppliers[index] = syncedSupplier;
    }
    _recordSyncChange(entityType: 'supplier', entityId: syncedSupplier.id, operation: isCreate ? 'create' : 'update', payload: syncedSupplier.toJson());
    await _saveDirty(suppliers: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteSupplier(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _suppliers.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    _suppliers[index] = _withSyncMeta<Supplier>(_suppliers[index].copyWith(deletedAt: now), now, clearDeletedAt: false);
    _recordSyncChange(entityType: 'supplier', entityId: id, operation: 'delete', payload: _suppliers[index].toJson());
    final affectedPrices = _softDeleteSupplierProductPrices(
      supplierId: id,
      now: now,
      reason: 'Supplier deleted',
    );
    await _saveDirty(suppliers: true, supplierProductPrices: affectedPrices > 0, sync: true);
    notifyListeners();
  }


  Future<void> addOrUpdateCategory(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_categories, item);
    _recordSyncChange(entityType: 'category', entityId: syncedItem.id, operation: _categories.where((existing) => existing.id == syncedItem.id).length == 1 && syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveDirty(categories: true, sync: true);
    notifyListeners();
  }

  Future<void> addOrUpdateBrand(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_brands, item);
    _recordSyncChange(entityType: 'brand', entityId: syncedItem.id, operation: syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveDirty(brands: true, sync: true);
    notifyListeners();
  }

  Future<void> addOrUpdateUnit(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_units, item);
    _recordSyncChange(entityType: 'unit', entityId: syncedItem.id, operation: syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveDirty(units: true, sync: true);
    notifyListeners();
  }

  CatalogItem _addOrUpdateCatalogItem(List<CatalogItem> list, CatalogItem item) {
    if (item.nameEn.trim().isEmpty && item.nameAr.trim().isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalizedEn = item.nameEn.trim().toLowerCase();
    final normalizedAr = item.nameAr.trim().toLowerCase();
    final duplicate = list.any((existing) {
      if (existing.id == item.id) return false;
      return (normalizedEn.isNotEmpty && existing.nameEn.trim().toLowerCase() == normalizedEn) ||
          (normalizedAr.isNotEmpty && existing.nameAr.trim().toLowerCase() == normalizedAr);
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

  Future<void> addOrUpdateExpense(Expense expense) async {
    requirePermission(AppPermission.expensesManage);
    if (expense.title.trim().isEmpty || expense.category.trim().isEmpty || !expense.amount.isFinite || expense.amount <= 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final now = DateTime.now();
    final index = _expenses.indexWhere((item) => item.id == expense.id);
    final isCreate = index == -1;
    if (!isCreate) {
      final current = _expenses[index];
      if (current.isPosted) {
        throw StateError('Posted expenses cannot be edited. Cancel them first.');
      }
      if (current.isCancelled) {
        throw StateError('Cancelled expenses cannot be edited.');
      }
    }
    final normalized = expense.copyWith(status: isCreate ? 'Draft' : expense.status);
    final syncedExpense = _withSyncMeta<Expense>(normalized, now, isCreate: isCreate);
    if (isCreate) {
      _expenses.add(syncedExpense);
    } else {
      _expenses[index] = syncedExpense;
    }
    _recordSyncChange(entityType: 'expense', entityId: syncedExpense.id, operation: isCreate ? 'create' : 'update', payload: syncedExpense.toJson());
    await _saveDirty(expenses: true, sync: true);
    notifyListeners();
  }

  Future<void> postExpense(String id) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isPosted || expense.isCancelled) return;
    final now = DateTime.now();
    final posted = _withSyncMeta<Expense>(expense.copyWith(status: 'Posted'), now);
    _expenses[index] = posted;
    _recordSyncChange(entityType: 'expense', entityId: id, operation: 'post', payload: posted.toJson());
    await _saveDirty(expenses: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteDraftExpense(String id) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (expense.isPosted) {
      throw StateError('Posted expenses cannot be deleted. Cancel them first.');
    }
    if (expense.isCancelled) {
      throw StateError('Cancelled expenses require permanent delete permission.');
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(expense.copyWith(deletedAt: now), now, clearDeletedAt: false);
    _expenses[index] = deleted;
    _recordSyncChange(entityType: 'expense', entityId: id, operation: 'delete', payload: deleted.toJson());
    await _saveDirty(expenses: true, sync: true);
    notifyListeners();
  }

  Future<void> cancelExpense(String id, {String reason = ''}) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isCancelled) return;
    if (!expense.isPosted) {
      throw StateError('Only posted expenses can be cancelled. Delete draft expenses instead.');
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
    _expenses[index] = cancelled;
    _recordSyncChange(entityType: 'expense', entityId: id, operation: 'cancel', payload: cancelled.toJson());
    await _saveDirty(expenses: true, sync: true);
    notifyListeners();
  }

  Future<void> permanentlyDeleteCancelledExpense(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (!expense.isCancelled) {
      throw StateError('Only cancelled expenses can be permanently deleted.');
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(expense.copyWith(deletedAt: now), now, clearDeletedAt: false);
    _expenses[index] = deleted;
    _recordSyncChange(entityType: 'expense', entityId: id, operation: 'permanent_delete', payload: deleted.toJson());
    await _saveDirty(expenses: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteExpense(String id) => deleteDraftExpense(id);


  String get _purchaseDevicePrefix => _deviceId.isEmpty ? 'LOCAL' : _deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase().padRight(4, '0').substring(0, 4);

  int _loadPurchaseCounter() {
    final raw = LocalDatabaseService.getString(_purchaseCounterKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<Warehouse> createWarehouse({required String name, String code = '', String location = ''}) async {
    requirePermission(AppPermission.productsEdit);
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) throw ArgumentError('Warehouse name is required.');
    _ensureDefaultWarehouse();
    if (_warehouses.any((item) => !item.isDeleted && item.name.toLowerCase() == cleanedName.toLowerCase())) {
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
    _recordSyncChange(entityType: 'warehouse', entityId: warehouse.id, operation: 'create', payload: warehouse.toJson());
    await _saveDirty(warehouses: true, sync: true);
    notifyListeners();
    return warehouse;
  }

  Future<void> transferStock({required String productId, required String fromWarehouseId, required String toWarehouseId, required double quantity, String notes = ''}) async {
    requirePermission(AppPermission.productsEdit);
    if (quantity <= 0) throw ArgumentError('Transfer quantity must be positive.');
    _ensureDefaultWarehouse();
    if (fromWarehouseId == toWarehouseId) throw ArgumentError('Choose two different warehouses.');
    final productIndex = _products.indexWhere((item) => item.id == productId);
    if (productIndex == -1) throw ArgumentError('Product not found.');
    final product = _products[productIndex];
    if (!product.trackStock) throw StateError('This product does not track stock.');
    final fromWarehouse = _warehouses.firstWhere((item) => item.id == fromWarehouseId && !item.isDeleted, orElse: () => throw ArgumentError('Source warehouse not found.'));
    final toWarehouse = _warehouses.firstWhere((item) => item.id == toWarehouseId && !item.isDeleted, orElse: () => throw ArgumentError('Destination warehouse not found.'));
    final available = stockForWarehouse(productId, fromWarehouseId);
    if (available < quantity) throw StateError('Not enough stock in ${fromWarehouse.name}.');
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    _addStockMovement(StockMovement(
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
    ), recordSync: true);
    _addStockMovement(StockMovement(
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
    ), recordSync: true);
    await _saveDirty(stockMovements: true, sync: true);
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
    if (items.isEmpty) throw ArgumentError('Purchase must contain at least one item.');
    for (final item in items) {
      if (item.quantity <= 0 || item.conversionToBase <= 0 || item.unitCost < 0) throw ArgumentError('Invalid purchase item values.');
      if (_findProductById(item.productId) == null) throw ArgumentError('Product not found: ${item.productName}');
    }
    _purchaseCounter += 1;
    final now = DateTime.now();
    final purchaseTotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final normalizedPaymentStatus = paymentStatus.trim().toLowerCase() == 'credit' ? 'credit' : paymentStatus.trim().toLowerCase() == 'partial' ? 'partial' : 'paid';
    final normalizedPaymentMethod = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final normalizedPaidAmount = normalizedPaymentStatus == 'paid' ? purchaseTotal : normalizedPaymentStatus == 'credit' ? 0.0 : (paidAmount ?? 0).clamp(0, purchaseTotal).toDouble();
    final purchase = Purchase(
      id: now.microsecondsSinceEpoch.toString(),
      purchaseNo: 'PO-$_purchaseDevicePrefix-${_purchaseCounter.toString().padLeft(6, '0')}',
      supplierId: supplierId,
      supplierName: supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
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
    _purchases.add(purchase);
    _recordSyncChange(entityType: 'purchase', entityId: purchase.id, operation: 'create', payload: purchase.toJson());
    if (receiveNow) {
      _applyPurchaseStock(purchase, now);
      _recordPurchaseLedger(purchase, now);
    }
    await _saveDirty(purchases: true, products: receiveNow, stockMovements: receiveNow, accountTransactions: receiveNow, purchaseCounter: true, sync: true);
    notifyListeners();
    return purchase;
  }

  Future<void> receivePurchase(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchases.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Purchase not found.');
    final purchase = _purchases[index];
    if (purchase.isReceived || purchase.isCancelled) return;
    final now = DateTime.now();
    final received = _withSyncMeta<Purchase>(purchase.copyWith(status: 'Received'), now);
    _purchases[index] = received;
    _recordSyncChange(entityType: 'purchase', entityId: received.id, operation: 'receive', payload: received.toJson());
    _applyPurchaseStock(received, now);
    _recordPurchaseLedger(received, now);
    await _saveDirty(purchases: true, products: true, stockMovements: true, accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteDraftPurchase(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchases.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final purchase = _purchases[index];
    if (purchase.isReceived) {
      throw StateError('Received purchase invoices cannot be deleted. Cancel them first.');
    }
    if (purchase.isCancelled) {
      throw StateError('Cancelled purchase invoices require permanent delete permission.');
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Purchase>(purchase.copyWith(deletedAt: now), now, clearDeletedAt: false);
    _purchases[index] = deleted;
    _recordSyncChange(entityType: 'purchase', entityId: id, operation: 'delete', payload: deleted.toJson());
    await _saveDirty(purchases: true, sync: true);
    notifyListeners();
  }

  Future<void> permanentlyDeleteCancelledPurchase(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _purchases.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final purchase = _purchases[index];
    if (purchase.status.toLowerCase() != 'cancelled') {
      throw StateError('Only cancelled purchase invoices can be permanently deleted.');
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Purchase>(purchase.copyWith(deletedAt: now), now, clearDeletedAt: false);
    _purchases[index] = deleted;
    _recordSyncChange(entityType: 'purchase', entityId: id, operation: 'permanent_delete', payload: deleted.toJson());
    await _saveDirty(purchases: true, sync: true);
    notifyListeners();
  }

  Future<void> returnPurchase(String id, {bool reverseStock = true, String reason = ''}) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchases.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Purchase not found.');
    final purchase = _purchases[index];
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError('Only received purchase invoices can be returned. Delete draft invoices instead.');
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && !purchase.reversalApplied) {
      for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _products.indexWhere((product) => product.id == item.productId);
        if (productIndex == -1) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        _products[productIndex] = _withSyncMeta<Product>(product.copyWith(stock: product.stock + qty), now);
        _addStockMovement(StockMovement(
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
        ), recordSync: true);
      }
      reversalApplied = true;
    }
    final returned = _withSyncMeta<Purchase>(purchase.copyWith(
      status: 'Returned',
      cancelledAt: now,
      cancelledByDeviceId: _deviceId,
      cancelReason: reason.trim(),
      reversalApplied: reversalApplied,
      note: 'Returned on ${now.toIso8601String()}',
    ), now);
    _purchases[index] = returned;
    _recordSyncChange(entityType: 'purchase', entityId: id, operation: 'return', payload: returned.toJson());
    _recordPurchaseCancelLedger(purchase, now, reason: reason, isReturn: true);
    await _saveDirty(purchases: true, products: reverseStock && !purchase.reversalApplied, stockMovements: reverseStock && !purchase.reversalApplied, accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<void> cancelPurchase(String id, {bool reverseStock = true, String reason = ''}) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _purchases.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Purchase not found.');
    final purchase = _purchases[index];
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError('Only received purchase invoices can be cancelled. Delete draft invoices instead.');
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && purchase.isReceived && !purchase.reversalApplied) {
      for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _products.indexWhere((product) => product.id == item.productId);
        if (productIndex == -1) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        _products[productIndex] = _withSyncMeta<Product>(product.copyWith(stock: product.stock + qty), now);
        _addStockMovement(StockMovement(
          id: '${purchase.id}-$lineIndex-${item.productId}-purchase-cancel',
          productId: item.productId,
          productName: item.productName,
          type: 'purchase_cancel',
          quantity: qty,
          date: now,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
          unitCost: item.unitCostPerBase,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ), recordSync: true);
      }
      reversalApplied = true;
    }
    final cancelled = _withSyncMeta<Purchase>(purchase.copyWith(
      status: 'Cancelled',
      cancelledAt: now,
      cancelledByDeviceId: _deviceId,
      cancelReason: reason.trim(),
      reversalApplied: reversalApplied,
    ), now);
    _purchases[index] = cancelled;
    _recordSyncChange(entityType: 'purchase', entityId: id, operation: 'cancel', payload: cancelled.toJson());
    _recordPurchaseCancelLedger(purchase, now, reason: reason);
    await _saveDirty(purchases: true, products: reverseStock && !purchase.reversalApplied, stockMovements: reverseStock && !purchase.reversalApplied, accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<void> adjustStock({required String productId, required double quantityDelta, required String reason, String adjustmentCategory = 'other', String notes = '', String evidenceRef = ''}) async {
    requirePermission(AppPermission.productsEdit);
    if (quantityDelta == 0) return;
    final index = _products.indexWhere((product) => product.id == productId);
    if (index == -1) throw ArgumentError('Product not found.');
    final now = DateTime.now();
    final product = _products[index];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    _products[index] = _withSyncMeta<Product>(product.copyWith(stock: product.stock + quantityDelta), now);
    _addStockMovement(StockMovement(
      id: '${now.microsecondsSinceEpoch}-$productId-adjustment',
      productId: productId,
      productName: product.name,
      type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
      quantity: quantityDelta,
      date: now,
      referenceId: productId,
      referenceNo: product.code,
      reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
      adjustmentCategory: adjustmentCategory.trim().isEmpty ? 'other' : adjustmentCategory.trim(),
      notes: notes.trim(),
      evidenceRef: evidenceRef.trim(),
      unitCost: product.usdCost,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    ), recordSync: true);
    await _saveDirty(products: true, stockMovements: true, sync: true);
    notifyListeners();
  }

  void _applyPurchaseStock(Purchase purchase, DateTime now) {
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final index = _products.indexWhere((product) => product.id == item.productId);
      if (index == -1) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final receivedQty = item.baseQuantity;
      final newStock = product.stock + receivedQty;
      final baseUnitCost = item.unitCostPerBase;
      final weightedCost = newStock <= 0
          ? baseUnitCost
          : ((product.stock * _safeUsdCost(product)) + (receivedQty * baseUnitCost)) / newStock;
      _products[index] = _withSyncMeta<Product>(product.copyWith(stock: newStock, cost: weightedCost, usdCost: weightedCost, originalCost: weightedCost, costCurrency: 'USD', costExchangeRateAtEntry: storeProfile.usdToLbpRate), now);
      _addStockMovement(StockMovement(
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
      ), recordSync: true);
    }
  }

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) {
    if (_stockMovements.any((item) => item.id == movement.id)) return;
    _stockMovements.add(movement);
    if (recordSync) {
      _recordSyncChange(entityType: 'stock_movement', entityId: movement.id, operation: movement.type, payload: movement.toJson());
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
    if (outputQuantity <= 0) throw ArgumentError('Output quantity must be greater than zero.');
    if (components.isEmpty) throw ArgumentError('BOM must contain at least one component.');
    final output = _findProductById(outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final cleanedComponents = <BillOfMaterialsLine>[];
    for (final component in components) {
      if (component.quantity <= 0) throw ArgumentError('Component quantity must be greater than zero.');
      if (component.productId == outputProductId) throw ArgumentError('Output product cannot be used as a component in the same BOM.');
      final product = _findProductById(component.productId);
      if (product == null) throw ArgumentError('Component product was not found.');
      cleanedComponents.add(component.copyWith(productName: product.name, unitCost: _safeUsdCost(product)));
    }
    final now = DateTime.now();
    final bom = _withSyncMeta<BillOfMaterials>(BillOfMaterials(
      id: '${now.microsecondsSinceEpoch}-bom',
      name: name.trim(),
      outputProductId: output.id,
      outputProductName: output.name,
      outputQuantity: outputQuantity,
      components: cleanedComponents,
      notes: notes.trim(),
    ), now, isCreate: true);
    _billsOfMaterials.add(bom);
    _recordSyncChange(entityType: 'bill_of_materials', entityId: bom.id, operation: 'create', payload: bom.toJson());
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
    if (quantity <= 0) throw ArgumentError('Manufacturing quantity must be greater than zero.');
    final bom = _billsOfMaterials.firstWhere((item) => item.id == bomId && !item.isDeleted && item.isActive, orElse: () => throw ArgumentError('BOM was not found.'));
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final factor = quantity / bom.outputQuantity;
    final warehouse = warehouseId.trim().isEmpty
        ? defaultWarehouse
        : warehouses.firstWhere((item) => item.id == warehouseId, orElse: () => defaultWarehouse);
    for (final component in bom.components) {
      final product = _findProductById(component.productId);
      if (product == null || !product.trackStock) continue;
      final requiredQty = component.quantity * factor;
      if (product.stock < requiredQty) {
        throw ArgumentError('Insufficient stock for ${product.name}. Required: $requiredQty, available: ${product.stock}.');
      }
    }
    final now = DateTime.now();
    final order = _withSyncMeta<ManufacturingOrder>(ManufacturingOrder(
      id: '${now.microsecondsSinceEpoch}-mfg',
      orderNo: 'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
      bomId: bom.id,
      bomName: bom.name,
      outputProductId: output.id,
      outputProductName: output.name,
      quantity: quantity,
      notes: notes.trim(),
      date: now,
    ), now, isCreate: true);

    for (var lineIndex = 0; lineIndex < bom.components.length; lineIndex += 1) {
      final component = bom.components[lineIndex];
      final index = _products.indexWhere((item) => item.id == component.productId);
      if (index == -1) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final usedQty = component.quantity * factor;
      _products[index] = _withSyncMeta<Product>(product.copyWith(stock: product.stock - usedQty), now);
      _addStockMovement(StockMovement(
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
      ), recordSync: true);
    }

    final outputIndex = _products.indexWhere((item) => item.id == output.id);
    if (outputIndex != -1 && output.trackStock) {
      final producedCost = bom.unitCost;
      _products[outputIndex] = _withSyncMeta<Product>(output.copyWith(stock: output.stock + quantity, cost: producedCost, usdCost: producedCost, originalCost: producedCost, costCurrency: 'USD', costExchangeRateAtEntry: storeProfile.usdToLbpRate), now);
      _addStockMovement(StockMovement(
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
      ), recordSync: true);
    }

    _manufacturingOrders.add(order);
    _recordSyncChange(entityType: 'manufacturing_order', entityId: order.id, operation: 'complete', payload: order.toJson());
    await _saveDirty(products: true, stockMovements: true, manufacturingOrders: true, sync: true);
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
    if (items.isEmpty) throw ArgumentError('Quotation must contain at least one item.');
    final cleanedDiscount = discount.isFinite ? discount.clamp(0, double.infinity).toDouble() : 0.0;
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) throw ArgumentError('Discount cannot be greater than subtotal.');
    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) throw ArgumentError('Invalid quotation item values.');
      if (_findProductById(item.productId) == null) throw ArgumentError('Product not found: ${item.productName}');
    }
    final now = DateTime.now();
    final quotation = SaleQuotation(
      id: now.microsecondsSinceEpoch.toString(),
      quotationNo: 'QTN-$_invoiceDevicePrefix-${(saleQuotations.length + 1).toString().padLeft(6, '0')}',
      customerName: customerName.trim().isEmpty ? walkInCustomerName : customerName.trim(),
      customerId: customerId.trim().isEmpty ? walkInCustomerId : customerId.trim(),
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
    _recordSyncChange(entityType: 'sale_quotation', entityId: quotation.id, operation: 'create', payload: quotation.toJson());
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return quotation;
  }

  Future<Sale> convertSaleQuotationToSale(String quotationId, {String paymentMethod = 'Cash', String paymentStatus = 'paid'}) async {
    requirePermission(AppPermission.salesCreate);
    final index = _saleQuotations.indexWhere((item) => item.id == quotationId);
    if (index == -1) throw ArgumentError('Quotation not found.');
    final quotation = _saleQuotations[index];
    if (quotation.isDeleted) throw StateError('Quotation is deleted.');
    if (quotation.isConverted) throw StateError('Quotation is already converted.');
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
    final updated = _withSyncMeta<SaleQuotation>(quotation.copyWith(status: 'Converted', convertedSaleId: sale.id, updatedAt: now), now);
    _saleQuotations[index] = updated;
    _recordSyncChange(entityType: 'sale_quotation', entityId: updated.id, operation: 'convert', payload: updated.toJson());
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return sale;
  }

  Future<void> deleteSaleQuotation(String id) async {
    requirePermission(AppPermission.salesCancel);
    final index = _saleQuotations.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<SaleQuotation>(_saleQuotations[index].copyWith(deletedAt: now, updatedAt: now), now);
    _saleQuotations[index] = deleted;
    _recordSyncChange(entityType: 'sale_quotation', entityId: id, operation: 'delete', payload: deleted.toJson());
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
  }



  DeliveryNote? deliveryNoteForSale(String saleId) {
    for (final note in _deliveryNotes) {
      if (!note.isDeleted && note.saleId == saleId) return note;
    }
    return null;
  }

  Future<DeliveryNote> createDeliveryNoteFromSale(String saleId, {String note = ''}) async {
    requirePermission(AppPermission.salesCreate);
    final saleIndex = _sales.indexWhere((item) => item.id == saleId);
    if (saleIndex == -1) throw ArgumentError('Sale not found.');
    final sale = _sales[saleIndex];
    if (sale.isDeleted) throw StateError('Sale is deleted.');
    if (sale.isCancelled) throw StateError('Cannot create a delivery note for a cancelled or returned sale.');
    final existing = deliveryNoteForSale(saleId);
    if (existing != null) return existing;
    final now = DateTime.now();
    final deliveryNote = DeliveryNote(
      id: '${now.microsecondsSinceEpoch}-delivery',
      deliveryNo: 'DLV-$_invoiceDevicePrefix-${(_deliveryNotes.where((item) => !item.isDeleted).length + 1).toString().padLeft(6, '0')}',
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
    _recordSyncChange(entityType: 'delivery_note', entityId: deliveryNote.id, operation: 'create', payload: deliveryNote.toJson());
    await _saveDirty(deliveryNotes: true, sync: true);
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
    final updated = _withSyncMeta<DeliveryNote>(current.copyWith(status: 'Delivered', deliveredAt: now, updatedAt: now), now);
    _deliveryNotes[index] = updated;
    _recordSyncChange(entityType: 'delivery_note', entityId: id, operation: 'deliver', payload: updated.toJson());
    await _saveDirty(deliveryNotes: true, sync: true);
    notifyListeners();
  }

  Future<void> deleteDeliveryNote(String id) async {
    requirePermission(AppPermission.salesCancel);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<DeliveryNote>(_deliveryNotes[index].copyWith(deletedAt: now, updatedAt: now), now);
    _deliveryNotes[index] = deleted;
    _recordSyncChange(entityType: 'delivery_note', entityId: id, operation: 'delete', payload: deleted.toJson());
    await _saveDirty(deliveryNotes: true, sync: true);
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

    _invoiceCounter += 1;
    final saleItems = items.map((item) {
      final product = _products.firstWhere((p) => p.id == item.productId);
      return SaleItem(
        productId: item.productId,
        productName: item.productName,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        unitName: item.unitName,
        baseQuantity: item.effectiveBaseQuantity,
        conversionToBase: item.conversionToBase,
        unitCost: item.unitCost > 0 ? item.unitCost : product.usdCost,
      );
    }).toList();

    final now = DateTime.now();
    final saleTotal = (saleItems.fold<double>(0, (sum, item) => sum + item.lineTotal) - cleanedDiscount).clamp(0, double.infinity).toDouble();
    final normalizedInvoiceCurrency = invoiceCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    final normalizedPaymentCurrency = paymentCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    final rate = (exchangeRateAtPayment ?? storeProfile.usdToLbpRate);
    final safeRate = rate <= 0 ? StoreProfile.defaults.usdToLbpRate : rate;
    final saleTotalInInvoiceCurrency = normalizedInvoiceCurrency == 'LBP' ? saleTotal * safeRate : saleTotal;
    final normalizedCustomerId = customerId.trim().isEmpty ? walkInCustomerId : customerId.trim();
    final normalizedCustomerName = customerName.trim().isEmpty ? walkInCustomerName : customerName.trim();
    final normalizedPaymentMethod = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final isWalkInSale = normalizedCustomerId == walkInCustomerId || normalizedCustomerName.toLowerCase() == walkInCustomerName.toLowerCase();
    if (isWalkInSale && normalizedPaymentMethod == 'Credit') {
      throw ArgumentError('Walk-in customer sales cannot be credit.');
    }
    final normalizedCashReceived = (cashReceivedAmount ?? (normalizedPaymentMethod == 'Cash' ? saleTotalInInvoiceCurrency : 0.0)).clamp(0, saleTotalInInvoiceCurrency).toDouble();
    final requestedStatus = paymentStatus.trim().toLowerCase();
    final normalizedPaymentStatus = normalizedPaymentMethod == 'Credit'
        ? (normalizedCashReceived > 0 ? 'partial' : 'credit')
        : (requestedStatus == 'credit' ? 'credit' : requestedStatus == 'partial' ? 'partial' : 'paid');
    final normalizedPaidAmount = normalizedPaymentMethod == 'Credit' ? normalizedCashReceived : saleTotalInInvoiceCurrency;
    final sale = Sale(
      id: now.microsecondsSinceEpoch.toString(),
      invoiceNo: 'INV-$_invoiceDevicePrefix-${_invoiceCounter.toString().padLeft(6, '0')}',
      customerName: normalizedCustomerName,
      customerId: normalizedCustomerId,
      date: now,
      status: 'Paid',
      paymentMethod: normalizedPaymentMethod,
      paymentStatus: normalizedPaymentStatus,
      invoiceCurrency: normalizedInvoiceCurrency,
      paymentCurrency: normalizedPaymentCurrency,
      exchangeRateAtPayment: safeRate,
      paidAmount: normalizedPaidAmount,
      cashReceivedAmount: normalizedCashReceived,
      paidAmountInPaymentCurrency: paidAmountInPaymentCurrency ?? normalizedPaidAmount,
      cashReceivedAmountInPaymentCurrency: cashReceivedAmountInPaymentCurrency ?? normalizedCashReceived,
      items: saleItems,
      discount: cleanedDiscount,
      originalDiscount: originalDiscount ?? cleanedDiscount,
      discountCurrency: discountCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
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
    _recordSyncChange(entityType: 'sale', entityId: sale.id, operation: 'create', payload: sale.toJson());

    for (var lineIndex = 0; lineIndex < saleItems.length; lineIndex += 1) {
      final item = saleItems[lineIndex];
      final index = _products.indexWhere((product) => product.id == item.productId);
      var product = _products[index];
      if (!product.trackStock) continue;

      final shortage = item.effectiveBaseQuantity - product.stock;
      if (shortage > 0) {
        final correctedStock = product.stock + shortage;
        product = _withSyncMeta<Product>(product.copyWith(stock: correctedStock), now);
        _products[index] = product;
        _addStockMovement(StockMovement(
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
          notes: 'Created automatically because available stock was insufficient during POS sale.',
          unitCost: item.unitCostPerBase,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ), recordSync: true);
      }

      final updatedProduct = _withSyncMeta<Product>(product.copyWith(stock: product.stock - item.effectiveBaseQuantity), now);
      _products[index] = updatedProduct;
      _addStockMovement(StockMovement(
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
      ), recordSync: true);
    }

    _recordSaleLedger(sale, now);
    await _saveDirty(products: true, sales: true, stockMovements: true, accountTransactions: true, invoiceCounter: true, sync: true);
    notifyListeners();
    return sale;
  }



  Future<void> returnSale(String id, {bool restoreStock = true}) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == id);
    if (index == -1) {
      throw ArgumentError('Sale not found.');
    }

    final sale = _sales[index];
    if (sale.isCancelled) return;

    if (restoreStock) {
      for (final item in sale.items) {
        final productIndex = _products.indexWhere((product) => product.id == item.productId);
        if (productIndex == -1) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final now = DateTime.now();
        final updatedProduct = _withSyncMeta<Product>(product.copyWith(stock: product.stock + item.effectiveBaseQuantity), now);
        _products[productIndex] = updatedProduct;
        _addStockMovement(StockMovement(
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
        ), recordSync: true);
      }
    }

    final now = DateTime.now();
    _sales[index] = _withSyncMeta<Sale>(sale.copyWith(status: 'Returned', note: 'Returned on ${now.toIso8601String()}'), now);
    _recordSyncChange(entityType: 'sale', entityId: id, operation: 'return', payload: _sales[index].toJson());
    _recordSaleCancelLedger(sale, now, isReturn: true);
    await _saveDirty(products: restoreStock, sales: true, stockMovements: restoreStock, accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<void> cancelSale(String id, {String status = 'Cancelled', bool restoreStock = true}) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == id);
    if (index == -1) {
      throw ArgumentError('Sale not found.');
    }

    final sale = _sales[index];
    if (sale.isCancelled) return;

    if (restoreStock) {
      for (final item in sale.items) {
        final productIndex = _products.indexWhere((product) => product.id == item.productId);
        if (productIndex == -1) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final now = DateTime.now();
        final updatedProduct = _withSyncMeta<Product>(product.copyWith(stock: product.stock + item.effectiveBaseQuantity), now);
        _products[productIndex] = updatedProduct;
        _addStockMovement(StockMovement(
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
        ), recordSync: true);
      }
    }

    final now = DateTime.now();
    _sales[index] = _withSyncMeta<Sale>(sale.copyWith(status: status, note: 'Stock restored on ${now.toIso8601String()}'), now);
    _recordSyncChange(entityType: 'sale', entityId: id, operation: 'cancel', payload: _sales[index].toJson());
    _recordSaleCancelLedger(sale, now);
    await _saveDirty(products: restoreStock, sales: true, stockMovements: restoreStock, accountTransactions: true, sync: true);
    notifyListeners();
  }

  @Deprecated('Use cancelSale instead. Invoices are cancelled, not physically deleted.')
  Future<void> deleteSale(String id, {bool restoreStock = true}) async {
    // Compatibility wrapper for older call sites. Business flow cancels invoices instead of deleting them.
    await cancelSale(id, status: 'Cancelled', restoreStock: restoreStock);
  }

  double estimateProfit() {
    final grossProfit = sales.fold<double>(0, (sum, sale) => sum + sale.grossProfit);
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

  Map<String, dynamic> _backupPayload({List<SyncChange>? changes, bool includeDeviceAndSyncState = true}) => {
        'version': 12,
        'generatedAt': DateTime.now().toIso8601String(),
        'schemaVersion': 17,
        if (!includeDeviceAndSyncState) 'backupType': 'business_backup',
        if (!includeDeviceAndSyncState) 'storeId': appIdentity.storeId,
        if (!includeDeviceAndSyncState) 'branchId': appIdentity.branchId,
        if (!includeDeviceAndSyncState) 'appVersion': 'stage2',
        if (!includeDeviceAndSyncState) 'platform': appIdentity.platform.name,
        if (!includeDeviceAndSyncState) 'themeMode': LocalDatabaseService.getString(_themeModeKey) ?? 'system',
        'invoiceCounter': _invoiceCounter,
        'purchaseCounter': _purchaseCounter,
        'storeProfile': _storeProfile.toJson(),
        'products': _products.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'customers': _customers.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'sales': _sales.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'saleQuotations': _saleQuotations.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'deliveryNotes': _deliveryNotes.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'billsOfMaterials': _billsOfMaterials.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'manufacturingOrders': _manufacturingOrders.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'suppliers': _suppliers.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'supplierProductPrices': _supplierProductPrices.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'categories': _categories.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'brands': _brands.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'units': _units.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'expenses': _expenses.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'purchases': _purchases.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'stockMovements': _stockMovements.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'warehouses': _warehouses.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        'accountTransactions': _accountTransactions.map((item) => includeDeviceAndSyncState ? item.toJson() : _businessBackupJson(item)).toList(),
        if (includeDeviceAndSyncState) 'deviceId': _deviceId,
        if (includeDeviceAndSyncState) 'syncChanges': (changes ?? _syncChanges).map((item) => item.toJson()).toList(),
        if (includeDeviceAndSyncState) 'syncQueue': _syncQueue.map((item) => item.toJson()).toList(),
        'roles': _roles.map((item) => item.toJson()).toList(),
        'users': _users.map((item) => item.toJson()).toList(),
        if (includeDeviceAndSyncState) 'appIdentity': appIdentity.toJson(),
        if (includeDeviceAndSyncState) 'storeEpoch': appIdentity.storeEpoch,
        'syncGeneratedAt': DateTime.now().toIso8601String(),
        'syncGeneratedSequence': _syncChanges.isEmpty ? 0 : _syncChanges.map((item) => item.sequence).reduce((a, b) => a > b ? a : b),
      };


  List<Map<String, dynamic>> exportCloudLoginBootstrapSnapshotChunks() {
    final identity = appIdentity;
    final generatedAt = DateTime.now().toIso8601String();
    final jobId = '${DateTime.now().microsecondsSinceEpoch}-$_deviceId-login-bootstrap';

    String encodeCompressed(Map<String, dynamic> payload) {
      final bytes = utf8.encode(jsonEncode(payload));
      final compressed = GZipEncoder().encode(bytes);
      return base64Encode(compressed);
    }

    final chunks = <Map<String, dynamic>>[];

    void addPayload(String collection, int index, Map<String, dynamic> payload) {
      chunks.add({
        'jobId': jobId,
        'storeId': identity.storeId,
        'branchId': identity.branchId,
        'deviceId': _deviceId,
        'collection': collection,
        'chunkIndex': index,
        'encoding': 'gzip+base64+json',
        'payload': encodeCompressed(payload),
        'generatedAt': generatedAt,
        'storeEpoch': identity.storeEpoch,
      });
    }

    addPayload('_meta', 0, {
      'version': 14,
      'generatedAt': generatedAt,
      'schemaVersion': 17,
      'invoiceCounter': _invoiceCounter,
      'purchaseCounter': _purchaseCounter,
      'storeProfile': _storeProfile.toJson(),
      'appIdentity': identity.toJson(),
      'storeEpoch': identity.storeEpoch,
      'syncGeneratedSequence': _syncChanges.isEmpty ? 0 : _syncChanges.map((item) => item.sequence).reduce((a, b) => a > b ? a : b),
    });
    addPayload('roles', 0, {'items': _roles.map((item) => item.toJson()).toList()});
    addPayload('users', 0, {'items': _users.map((item) => item.toJson()).toList()});

    final sectionTotals = <String, int>{};
    final sectionSeen = <String, int>{};
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString();
      sectionTotals[collection] = (sectionTotals[collection] ?? 0) + 1;
    }
    final allSections = sectionTotals.keys.toList(growable: false);
    for (var i = 0; i < chunks.length; i += 1) {
      final collection = (chunks[i]['collection'] ?? '').toString();
      final sectionIndex = sectionSeen[collection] ?? 0;
      sectionSeen[collection] = sectionIndex + 1;
      chunks[i]['totalChunks'] = chunks.length;
      chunks[i]['ordinal'] = i;
      chunks[i]['sectionChunkIndex'] = sectionIndex;
      chunks[i]['sectionTotalChunks'] = sectionTotals[collection] ?? 1;
      chunks[i]['allSections'] = allSections;
    }
    return chunks;
  }


  List<Map<String, dynamic>> exportCloudBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) {
    final identity = appIdentity;
    final generatedAt = DateTime.now().toIso8601String();
    final jobId = '${DateTime.now().microsecondsSinceEpoch}-$_deviceId-bootstrap';
    final collections = <String, List<dynamic>>{
      // Login-critical records must be published before heavy business data.
      // A new Cloud Client can leave Connect to Store as soon as these chunks
      // are available, then continue the remaining snapshot after login.
      'roles': _roles.map((item) => item.toJson()).toList(),
      'users': _users.map((item) => item.toJson()).toList(),
      'categories': _categories.map((item) => item.toJson()).toList(),
      'brands': _brands.map((item) => item.toJson()).toList(),
      'units': _units.map((item) => item.toJson()).toList(),
      'warehouses': _warehouses.map((item) => item.toJson()).toList(),
      'products': _products.map((item) => item.toJson()).toList(),
      'customers': _customers.map((item) => item.toJson()).toList(),
      'suppliers': _suppliers.map((item) => item.toJson()).toList(),
      'supplierProductPrices': _supplierProductPrices.map((item) => item.toJson()).toList(),
      'sales': _sales.map((item) => item.toJson()).toList(),
      'saleQuotations': _saleQuotations.map((item) => item.toJson()).toList(),
      'deliveryNotes': _deliveryNotes.map((item) => item.toJson()).toList(),
      'billsOfMaterials': _billsOfMaterials.map((item) => item.toJson()).toList(),
      'manufacturingOrders': _manufacturingOrders.map((item) => item.toJson()).toList(),
      'expenses': _expenses.map((item) => item.toJson()).toList(),
      'purchases': _purchases.map((item) => item.toJson()).toList(),
      'stockMovements': _stockMovements.map((item) => item.toJson()).toList(),
      'accountTransactions': _accountTransactions.map((item) => item.toJson()).toList(),
    };

    String encodeCompressed(Map<String, dynamic> payload) {
      final bytes = utf8.encode(jsonEncode(payload));
      final compressed = GZipEncoder().encode(bytes);
      return base64Encode(compressed);
    }

    final chunks = <Map<String, dynamic>>[];
    void addEncodedPayload(String collection, int index, Map<String, dynamic> payload, String encoded) {
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

    void addPayload(String collection, int index, Map<String, dynamic> payload) {
      addEncodedPayload(collection, index, payload, encodeCompressed(payload));
    }

    addPayload('_meta', 0, {
      'version': 14,
      'generatedAt': generatedAt,
      'schemaVersion': 17,
      'invoiceCounter': _invoiceCounter,
      'purchaseCounter': _purchaseCounter,
      'storeProfile': _storeProfile.toJson(),
      'appIdentity': identity.toJson(),
      'storeEpoch': identity.storeEpoch,
      'syncGeneratedSequence': _syncChanges.isEmpty ? 0 : _syncChanges.map((item) => item.sequence).reduce((a, b) => a > b ? a : b),
    });

    collections.forEach((collection, list) {
      var chunkIndex = 0;
      if (list.isEmpty) {
        addPayload(collection, chunkIndex, {'items': const <dynamic>[]});
        return;
      }

      void addRange(int start, int end) {
        final count = end - start;
        final payload = {'items': list.sublist(start, end)};
        final encoded = encodeCompressed(payload);
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

    final sectionTotals = <String, int>{};
    final sectionSeen = <String, int>{};
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString();
      sectionTotals[collection] = (sectionTotals[collection] ?? 0) + 1;
    }
    final allSections = sectionTotals.keys.toList(growable: false);
    for (var i = 0; i < chunks.length; i += 1) {
      final collection = (chunks[i]['collection'] ?? '').toString();
      final sectionIndex = sectionSeen[collection] ?? 0;
      sectionSeen[collection] = sectionIndex + 1;
      chunks[i]['totalChunks'] = chunks.length;
      chunks[i]['ordinal'] = i;
      chunks[i]['sectionChunkIndex'] = sectionIndex;
      chunks[i]['sectionTotalChunks'] = sectionTotals[collection] ?? 1;
      chunks[i]['allSections'] = allSections;
    }
    return chunks;
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
    final recoveryKey = payload['recoveryKey']?.toString().trim().toUpperCase() ?? '';
    if (!storeId.startsWith('ST-') || branchId.isEmpty || !recoveryKey.startsWith('RK-')) {
      throw ArgumentError('Recovery file is missing required store identity fields.');
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
    final canonical = jsonEncode(Map.fromEntries(copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    var hash = 2166136261;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String exportBackupJson() {
    requirePermission(AppPermission.backupExport);
    return const JsonEncoder.withIndent('  ').convert(_backupPayload(includeDeviceAndSyncState: false));
  }

  String exportSyncSnapshotJson() => const JsonEncoder.withIndent('  ').convert(_backupPayload());

  DateTime syncSnapshotGeneratedAtFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return DateTime.tryParse(decoded['syncGeneratedAt']?.toString() ?? '') ?? DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  int syncSnapshotGeneratedSequenceFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  String exportSyncChangesJson({DateTime? since, int? sinceSequence}) {
    final sequenceFloor = sinceSequence ?? 0;
    final earliestSequence = _earliestStoredAuthoritativeSequence();
    final latestSequence = _latestStoredAuthoritativeSequence();

    // If a client asks for an old sequence that has already been compacted,
    // incremental delivery cannot be trusted. The client must rebuild from a
    // full Host snapshot instead of silently accepting a partial event stream.
    final needsSnapshot = sequenceFloor > 0 &&
        latestSequence > sequenceFloor &&
        earliestSequence > 0 &&
        sequenceFloor < earliestSequence - 1;

    final changes = needsSnapshot
        ? <SyncChange>[]
        : (_syncChanges.where((item) {
            if (sequenceFloor > 0) return item.sequence > sequenceFloor;
            if (since != null) return !item.createdAt.isBefore(since);
            return true;
          }).toList()..sort((a, b) => a.sequence.compareTo(b.sequence)));
    final cursor = changes.isEmpty
        ? (since ?? DateTime.fromMillisecondsSinceEpoch(0))
        : changes.map((item) => item.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final generatedSequence = needsSnapshot
        ? latestSequence
        : (changes.isEmpty
            ? sequenceFloor
            : changes.map((item) => item.sequence).reduce((a, b) => a > b ? a : b));
    return jsonEncode({
      'ok': true,
      'deviceId': _deviceId,
      'generatedAt': cursor.toIso8601String(),
      'generatedSequence': generatedSequence,
      'earliestSequence': earliestSequence,
      'latestSequence': latestSequence,
      'requestedSinceSequence': sequenceFloor,
      'needsSnapshot': needsSnapshot,
      'changes': changes.map((item) => item.toJson()).toList(),
    });
  }

  String _recoverySignature(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(Map.fromEntries(copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    final storeSecret = "${copy['storeId'] ?? ''}|${copy['branchId'] ?? ''}|${copy['recoveryKey'] ?? ''}|${copy['storeEpoch'] ?? ''}";
    return Hmac(sha256, utf8.encode(storeSecret)).convert(utf8.encode(canonical)).toString();
  }

  String exportEncryptedBackupJson(String password) {
    requirePermission(AppPermission.backupExport);
    final cleaned = password.trim();
    if (cleaned.length < 8) {
      throw ArgumentError('Backup password must be at least 8 characters.');
    }
    final plain = utf8.encode(exportBackupJson());
    final salt = _generateSalt();
    final nonce = _generateNonce();
    final key = _deriveBackupKey(cleaned, salt);
    final encrypted = _aesGcmEncrypt(plain, key, base64Url.decode(nonce));
    final payload = {
      'format': 'store_manager_pro_encrypted_backup',
      'version': 3,
      'kdf': 'pbkdf2-hmac-sha256-200000',
      'cipher': 'aes-256-gcm',
      'salt': salt,
      'nonce': nonce,
      'data': base64UrlEncode(encrypted),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String decryptBackupJson(String encryptedBackup, String password) {
    final decoded = jsonDecode(encryptedBackup) as Map<String, dynamic>;
    if (decoded['format'] != 'store_manager_pro_encrypted_backup') {
      return encryptedBackup;
    }
    final salt = decoded['salt'] as String? ?? '';
    final data = decoded['data'] as String? ?? '';
    if (salt.isEmpty || data.isEmpty) throw ArgumentError('Invalid encrypted backup.');

    // Backward compatibility with older backups created by the previous XOR-v1
    // format. New exports use an authenticated stream with a nonce and MAC.
    if ((decoded['version'] as num? ?? 1).toInt() < 2) {
      final key = _deriveBackupKeyV1(password.trim(), salt);
      final encrypted = base64Url.decode(data);
      final plain = List<int>.generate(encrypted.length, (index) => encrypted[index] ^ key[index % key.length]);
      return utf8.decode(plain);
    }

    final nonce = decoded['nonce'] as String? ?? '';
    if (nonce.isEmpty) throw ArgumentError('Invalid encrypted backup.');
    final encrypted = base64Url.decode(data);

    if ((decoded['version'] as num? ?? 2).toInt() == 2) {
      // Backward compatibility with backups exported by the authenticated
      // SHA-256 stream format. New exports use AES-256-GCM below.
      final macText = decoded['mac'] as String? ?? '';
      if (macText.isEmpty) throw ArgumentError('Invalid encrypted backup.');
      final legacyKey = _deriveBackupKeyV2(password.trim(), salt);
      final expectedMac = Hmac(sha256, legacyKey).convert([...utf8.encode(nonce), ...encrypted]).bytes;
      final actualMac = base64Url.decode(macText);
      if (!_constantTimeEquals(expectedMac, actualMac)) {
        throw ArgumentError('Invalid backup password or corrupted encrypted backup.');
      }
      final plain = _xorWithSha256Stream(encrypted, legacyKey, nonce);
      return utf8.decode(plain);
    }

    final key = _deriveBackupKey(password.trim(), salt);
    try {
      return utf8.decode(_aesGcmDecrypt(encrypted, key, base64Url.decode(nonce)));
    } catch (_) {
      throw ArgumentError('Invalid backup password or corrupted encrypted backup.');
    }
  }

  List<int> _deriveBackupKey(String password, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), 200000, 32));
    return derivator.process(Uint8List.fromList(utf8.encode('store_manager_pro|backup_v3|$password')));
  }

  List<int> _deriveBackupKeyV2(String password, String salt) {
    List<int> digest = utf8.encode('store_manager_pro|backup_v2|$salt|$password');
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

  List<int> _aesGcmDecrypt(List<int> encrypted, List<int> key, List<int> nonce) {
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
    List<int> digest = utf8.encode('store_manager_pro|backup_v1|$salt|$password');
    for (var i = 0; i < 25000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  List<int> _xorWithSha256Stream(List<int> input, List<int> key, String nonce) {
    final output = <int>[];
    var counter = 0;
    while (output.length < input.length) {
      final block = sha256.convert([...key, ...utf8.encode(nonce), ...utf8.encode(counter.toString())]).bytes;
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

  Future<void> importBackupJson(String rawJson) async {
    requirePermission(AppPermission.backupRestore);
    if (appIdentity.isClient) {
      throw StateError('Import Backup is only available on the Host device.');
    }
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map((item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ?? (decoded['quotations'] as List<dynamic>?) ?? const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map((item) => SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map((item) => DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final billsOfMaterials = (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
        .map((item) => BillOfMaterials.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final manufacturingOrders = (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
        .map((item) => ManufacturingOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final supplierProductPrices = (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
        .map((item) => SupplierProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map((item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map((item) => StockMovement.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map((item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final accountTransactions = (decoded['accountTransactions'] as List<dynamic>? ?? [])
        .map((item) => AccountTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map((item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(Map<String, dynamic>.from(decoded['storeProfile'] as Map));

    _products
      ..clear()
      ..addAll(products);
    _customers
      ..clear()
      ..addAll(customers);
    _sales
      ..clear()
      ..addAll(sales);
    _deliveryNotes
      ..clear()
      ..addAll(deliveryNotes);
    _billsOfMaterials
      ..clear()
      ..addAll(billsOfMaterials);
    _manufacturingOrders
      ..clear()
      ..addAll(manufacturingOrders);
    _saleQuotations
      ..clear()
      ..addAll(saleQuotations);
    _suppliers
      ..clear()
      ..addAll(suppliers);
    _supplierProductPrices
      ..clear()
      ..addAll(supplierProductPrices);
    _categories
      ..clear()
      ..addAll(categories);
    _brands
      ..clear()
      ..addAll(brands);
    _units
      ..clear()
      ..addAll(units);
    _ensureCatalogDefaults();
    _expenses
      ..clear()
      ..addAll(expenses);
    _purchases
      ..clear()
      ..addAll(purchases);
    _stockMovements
      ..clear()
      ..addAll(stockMovements);
    _warehouses
      ..clear()
      ..addAll(warehouses);
    _ensureDefaultWarehouse();
    _accountTransactions
      ..clear()
      ..addAll(accountTransactions);
    _invalidateAccountLedgerCache();
    _syncChanges.clear();
    _storeProfile = profile;
    // Business Backup may restore the permanent Store/Branch identity,
    // but it must never replace this device identity, role, tokens, pairing data, cursors, or Recovery Key.
    final importedStoreId = decoded['storeId']?.toString().trim() ?? '';
    final importedBranchId = decoded['branchId']?.toString().trim() ?? '';
    _appIdentity = appIdentity.copyWith(
      storeId: importedStoreId.isNotEmpty ? importedStoreId.toUpperCase() : appIdentity.storeId,
      branchId: importedBranchId.isNotEmpty ? importedBranchId.toUpperCase() : appIdentity.branchId,
      deviceId: _deviceId,
      platform: _detectPlatform(),
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    if (decoded['themeMode'] is String) {
      await LocalDatabaseService.setString(_themeModeKey, decoded['themeMode'].toString());
    }
    await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    if (roles.isNotEmpty) {
      _roles
        ..clear()
        ..addAll(roles);
    }
    if (users.isNotEmpty) {
      _replaceUsersWithoutDuplicates(users);
    }
    await _ensureDefaultAdminUser();
    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    _invoiceCounter = importedCounter > 0 ? importedCounter : _loadInvoiceCounter();
    final importedPurchaseCounter = (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
    _purchaseCounter = importedPurchaseCounter > 0 ? importedPurchaseCounter : _loadPurchaseCounter();
    _normalizeCustomers();
    // Manual Business Backup import is local business-data restore only.
    // It does not create sync events; Host snapshots are managed by the sync engine.

    await _saveAll();
    notifyListeners();
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
      if (current == null || (user.updatedAt ?? user.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(current.updatedAt ?? current.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))) {
        byUsername[key] = user.copyWith(username: key);
      }
    }
    return byUsername.values.toList();
  }

  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) {
    _users
      ..clear()
      ..addAll(_dedupeUsersByUsername(incoming));
    if (_activeUser != null && !_users.any((user) => user.id == _activeUser!.id && user.isActive)) {
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
      final sameNameIndex = merged.indexWhere((user) => user.username.trim().toLowerCase() == remoteName);
      final index = sameIdIndex != -1 ? sameIdIndex : sameNameIndex;
      final normalizedRemote = remote.copyWith(username: remoteName);
      if (index == -1) {
        merged.add(normalizedRemote);
      } else if ((normalizedRemote.updatedAt ?? normalizedRemote.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(merged[index].updatedAt ?? merged[index].createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))) {
        merged[index] = normalizedRemote;
      }
    }
    _replaceUsersWithoutDuplicates(merged);
  }

  void _mergeByUpdatedAt<T>(List<T> local, List<T> incoming, String Function(T item) idOf) {
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

  Future<void> mergeBackupJson(String rawJson, {bool markSynced = false}) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map((item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ?? (decoded['quotations'] as List<dynamic>?) ?? const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map((item) => SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map((item) => DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final billsOfMaterials = (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
        .map((item) => BillOfMaterials.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final manufacturingOrders = (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
        .map((item) => ManufacturingOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final supplierProductPrices = (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
        .map((item) => SupplierProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map((item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map((item) => StockMovement.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map((item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final accountTransactions = (decoded['accountTransactions'] as List<dynamic>? ?? [])
        .map((item) => AccountTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map((item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    _mergeByUpdatedAt<Product>(_products, products, (item) => item.id);
    _mergeByUpdatedAt<Customer>(_customers, customers, (item) => item.id);
    _mergeByUpdatedAt<Sale>(_sales, sales, (item) => item.id);
    _mergeByUpdatedAt<SaleQuotation>(_saleQuotations, saleQuotations, (item) => item.id);
    _mergeByUpdatedAt<DeliveryNote>(_deliveryNotes, deliveryNotes, (item) => item.id);
    _mergeByUpdatedAt<BillOfMaterials>(_billsOfMaterials, billsOfMaterials, (item) => item.id);
    _mergeByUpdatedAt<ManufacturingOrder>(_manufacturingOrders, manufacturingOrders, (item) => item.id);
    _mergeByUpdatedAt<Supplier>(_suppliers, suppliers, (item) => item.id);
    _mergeByUpdatedAt<SupplierProductPrice>(_supplierProductPrices, supplierProductPrices, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_categories, categories, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_brands, brands, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_units, units, (item) => item.id);
    _mergeByUpdatedAt<Expense>(_expenses, expenses, (item) => item.id);
    _mergeByUpdatedAt<Purchase>(_purchases, purchases, (item) => item.id);
    _mergeByUpdatedAt<StockMovement>(_stockMovements, stockMovements, (item) => item.id);
    _mergeByUpdatedAt<Warehouse>(_warehouses, warehouses, (item) => item.id);
    _ensureDefaultWarehouse();
    _mergeByUpdatedAt<AccountTransaction>(_accountTransactions, accountTransactions, (item) => item.id);
    _invalidateAccountLedgerCache();
    if (decoded['storeProfile'] != null) {
      _storeProfile = StoreProfile.fromJson(Map<String, dynamic>.from(decoded['storeProfile'] as Map));
    }
    // Never overwrite the local device identity during LAN pull/merge.
    // The remote snapshot belongs to the Host, while this device must keep
    // its own deviceId/deviceName/role so new local changes are queued
    // correctly toward the Host.
    _appIdentity = appIdentity.copyWith(deviceId: _deviceId, platform: _detectPlatform());
    await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    _mergeByUpdatedAt<UserRole>(_roles, roles, (item) => item.id);
    _mergeUsersWithoutUsernameDuplicates(users);
    final nowForMergedRemoteChanges = DateTime.now();
    _mergeSyncChanges(markSynced
        ? syncChanges
        : syncChanges.map((change) {
            if (change.deviceId == _deviceId || change.isSynced) return change;
            return change.copyWith(isSynced: true, syncedAt: nowForMergedRemoteChanges);
          }).toList());

    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    if (importedCounter > _invoiceCounter) _invoiceCounter = importedCounter;
    final importedPurchaseCounter = (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
    if (importedPurchaseCounter > _purchaseCounter) _purchaseCounter = importedPurchaseCounter;

    if (markSynced) {
      final now = DateTime.now();
      for (var i = 0; i < _syncChanges.length; i++) {
        _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
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
      throw StateError('Host devices cannot be converted to Clients by importing a sync snapshot.');
    }
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    await _replaceFromBackupMap(decoded, preserveLocalIdentityForLanClient: true);
  }

  Future<void> _replaceFromBackupMap(
    Map<String, dynamic> decoded, {
    bool preserveLocalIdentityForLanClient = false,
  }) async {
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map((item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ?? (decoded['quotations'] as List<dynamic>?) ?? const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map((item) => SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map((item) => DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final billsOfMaterials = (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
        .map((item) => BillOfMaterials.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final manufacturingOrders = (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
        .map((item) => ManufacturingOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final supplierProductPrices = (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
        .map((item) => SupplierProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map((item) => CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map((item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map((item) => StockMovement.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map((item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final accountTransactions = (decoded['accountTransactions'] as List<dynamic>? ?? [])
        .map((item) => AccountTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map((item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(Map<String, dynamic>.from(decoded['storeProfile'] as Map));

    _products..clear()..addAll(products);
    _customers..clear()..addAll(customers);
    _sales..clear()..addAll(sales);
    _saleQuotations..clear()..addAll(saleQuotations);
    _deliveryNotes..clear()..addAll(deliveryNotes);
    _billsOfMaterials..clear()..addAll(billsOfMaterials);
    _manufacturingOrders..clear()..addAll(manufacturingOrders);
    _suppliers..clear()..addAll(suppliers);
    _supplierProductPrices..clear()..addAll(supplierProductPrices);
    _categories..clear()..addAll(categories);
    _brands..clear()..addAll(brands);
    _units..clear()..addAll(units);
    _expenses..clear()..addAll(expenses);
    _purchases..clear()..addAll(purchases);
    _stockMovements..clear()..addAll(stockMovements);
    _warehouses..clear()..addAll(warehouses);
    _ensureDefaultWarehouse();
    _accountTransactions..clear()..addAll(accountTransactions);
    _invalidateAccountLedgerCache();
    _syncChanges
      ..clear()
      ..addAll(preserveLocalIdentityForLanClient
          ? syncChanges.map((item) => item.copyWith(isSynced: true, syncedAt: DateTime.now()))
          : syncChanges);
    _syncQueue.clear();
    if (!preserveLocalIdentityForLanClient) _syncQueue.addAll(syncQueue);
    _storeProfile = profile;
    if (preserveLocalIdentityForLanClient) {
      _appIdentity = _identityForLanSnapshotImport(decoded);
      await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    } else if (decoded['appIdentity'] is Map) {
      _appIdentity = AppIdentity.fromJson(Map<String, dynamic>.from(decoded['appIdentity'] as Map)).copyWith(
        deviceId: _deviceId,
        platform: _detectPlatform(),
      );
      await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
    }
    if (roles.isNotEmpty) _roles..clear()..addAll(roles);
    if (users.isNotEmpty) _replaceUsersWithoutDuplicates(users);
    await _ensureDefaultAdminUser();
    _invoiceCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? _invoiceCounter;
    _purchaseCounter = (decoded['purchaseCounter'] as num?)?.toInt() ?? _purchaseCounter;
    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }


  Future<int> removeLegacyCloudBootstrapSnapshotQueue() async {
    final identity = appIdentity;
    if (!identity.isHost || !identity.isCloudEnabled) return 0;
    final legacyIds = _syncChanges
        .where((change) =>
            change.entityType == 'system' &&
            change.entityId == 'store' &&
            change.operation == 'restore_snapshot' &&
            change.storeId == identity.storeId &&
            !change.isSynced)
        .map((change) => change.id)
        .toSet();
    if (legacyIds.isEmpty) return 0;
    _syncChanges.removeWhere((change) => legacyIds.contains(change.id));
    _syncQueue.removeWhere((item) => legacyIds.contains(item.changeId));
    await _saveSyncStateOnly();
    notifyListeners();
    return legacyIds.length;
  }


  Future<void> ensureHostCloudBootstrapSnapshotQueued({bool force = false}) async {
    // Safety fix: Cloud bootstrap snapshots must not be stored as giant
    // restore_snapshot SyncChange rows. They are now published directly to the
    // Cloud materialized snapshot endpoint in compressed chunks by
    // CloudSyncService._publishBootstrapSnapshotToCloud(). Keep this method as
    // a compatibility no-op so older call-sites no longer bloat the local Hive DB.
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
      if (change.storeId.isNotEmpty && change.storeId != identity.storeId) continue;
      if (change.branchId.isNotEmpty && change.branchId != identity.branchId) continue;
      if (change.deviceId == 'cloud-snapshot') continue;
      // Host only publishes authoritative Host events to Cloud. Client draft
      // commands must first be accepted/restamped by the Host.
      final meta = Map<String, dynamic>.from(change.payload['_syncV2'] as Map? ?? const {});
      final kind = (meta['kind'] ?? '').toString();
      final isAuthoritative = kind.isEmpty || kind == 'authoritativeEvent' || change.deviceId == _deviceId;
      if (!isAuthoritative) continue;
      if (existingCloudQueueIds.contains(change.id)) continue;
      if (existingAnyCloudQueueIds.contains(change.id)) {
        // If a cloud queue row exists but is synced while the change is still
        // unsynced, revive it as pending instead of adding a duplicate row.
        for (var i = 0; i < _syncQueue.length; i++) {
          final item = _syncQueue[i];
          if (item.target == 'cloud' && item.changeId == change.id && item.status == 'synced') {
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
    if (change.storeId.isNotEmpty && change.storeId != appIdentity.storeId) return false;
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
    final pendingChanges = result['pendingChanges'] ?? pendingSyncChanges.length;
    final remainingQueue = result['remainingQueue'] ?? _syncQueue.length;
    final remainingChanges = result['remainingChanges'] ?? _syncChanges.length;
    final safeFloorSequence = result['safeFloorSequence'] ?? 0;
    final earliestSequence = result['earliestSequence'] ?? _earliestStoredAuthoritativeSequence();
    final latestSequence = result['latestSequence'] ?? _latestStoredAuthoritativeSequence();
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
  Future<Map<String, int>> compactSyncedSyncHistoryForDiagnostics({int keepRecentSyncedChanges = _syncMaintenanceKeepRecentChanges}) async {
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

    debugPrint(_syncHistoryCompactionLogLine('BEFORE_AUTO_COMPACT_SYNC_HISTORY', before));
    final result = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: true,
      knownSafeFloorSequence: safeFloorSequence,
    );
    debugPrint(_syncHistoryCompactionLogLine('AFTER_AUTO_COMPACT_SYNC_HISTORY', result));
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
      debugPrint('CLIENT_SYNC_STALE_QUEUE_CLEANUP removedQueue=$removedStaleQueue '
          'remainingQueue=${_syncQueue.length} pendingQueue=${pendingSyncQueue.length}');
    }
    if (pendingSyncQueue.isNotEmpty || pendingSyncChanges.isNotEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ?? (_syncQueue.length + removedStaleQueue),
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
          beforeQueue: before['remainingQueue'] ?? (_syncQueue.length + removedStaleQueue),
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
      (item) => item.isSynced && item.sequence > 0 && item.sequence <= latestAppliedSequence,
    ) && _syncChanges.where((item) => item.isSynced && item.sequence > 0).length > keepRecentSyncedChanges;
    final hasSyncedLocalDrafts = _syncChanges.any((item) => item.isSynced && item.sequence <= 0);
    if (!hasAuthoritativeHistoryOverRetention && !hasSyncedLocalDrafts && _syncQueue.isEmpty) {
      if (removedStaleQueue > 0) {
        await _saveSyncStateOnly();
        notifyListeners();
        return _syncHistoryCompactionResult(
          beforeChanges: before['remainingChanges'] ?? _syncChanges.length,
          beforeQueue: before['remainingQueue'] ?? (_syncQueue.length + removedStaleQueue),
          safeFloorSequence: latestAppliedSequence,
          skipped: 1,
        );
      }
      return Map<String, int>.from(before)..['skipped'] = 1;
    }

    debugPrint(_syncHistoryCompactionLogLine('BEFORE_CLIENT_AUTO_COMPACT_SYNC_HISTORY', before));
    final rawResult = await _compactSyncedSyncHistory(
      keepRecentSyncedChanges: keepRecentSyncedChanges,
      requireSafeFloorSequence: false,
      knownSafeFloorSequence: latestAppliedSequence,
    );
    final result = Map<String, int>.from(rawResult);
    if (removedStaleQueue > 0) {
      result['removedQueue'] = (result['removedQueue'] ?? 0) + removedStaleQueue;
      result['remainingQueue'] = _syncQueue.length;
      result['pendingQueue'] = pendingSyncQueue.length;
      result['pendingChanges'] = pendingSyncChanges.length;
    }
    debugPrint(_syncHistoryCompactionLogLine('AFTER_CLIENT_AUTO_COMPACT_SYNC_HISTORY', result));
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
          if (!requireSafeFloorSequence && change != null && change.isSynced && change.sequence <= 0) {
            return false;
          }
          return true;
        })
        .map((item) => item.changeId)
        .toSet();

    final safeFloorSequence = knownSafeFloorSequence ?? _minimumActivePeerAckSequence();
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
    }).toList()..sort((a, b) => b.sequence.compareTo(a.sequence));
    final keepSyncedIds = syncedChanges.take(keepRecentSyncedChanges).map((item) => item.id).toSet();

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
    if ((result['removedChanges'] ?? 0) > 0 || (result['removedQueue'] ?? 0) > 0) {
      await _saveSyncStateOnly();
      notifyListeners();
    }
    return result;
  }

  void _enqueueSyncChangeForTarget(String changeId, String target, DateTime now) {
    if (_syncQueue.any((item) => item.changeId == changeId && item.target == target)) return;
    _syncQueue.add(SyncQueueItem(
      id: '$changeId-$target',
      changeId: changeId,
      target: target,
      status: 'pending',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToCloud = false,
  }) async {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    final existingEventIds = _syncChanges.map((item) => _syncMetaString(item, 'eventId')).where((item) => item.isNotEmpty).toSet();
    final acceptedSourceCommandIds = _syncChanges.map((item) => _syncMetaString(item, 'sourceCommandId')).where((item) => item.isNotEmpty).toSet();
    final lastAppliedSequence = SyncDeviceStateStore.load(appIdentity).lastAppliedSequence;
    final currentEpoch = appIdentity.storeEpoch;
    final sorted = [...incoming]
      ..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) return a.sequence.compareTo(b.sequence);
        return a.createdAt.compareTo(b.createdAt);
      });
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

    void markEntityDirty(SyncChange change) {
      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data' || change.operation == 'restore_snapshot') {
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
        continue;
      }
      final incomingEpoch = change.storeEpoch;
      if (incomingEpoch < currentEpoch && !(change.entityType == 'system' && change.operation == 'reset_store_data')) {
        continue;
      }
      await _applySyncChangePayload(change);
      markEntityDirty(change);
      final shouldMirrorToCloud = mirrorToCloud && _shouldMirrorRemoteChangeToCloud(change);

      // Host-authority sync note:
      // Any draft accepted by the Host must become a new authoritative Host
      // event, even in LAN-only mode. v12 only restamped events that were also
      // mirrored to Cloud; pure Local/LAN installs kept the original Client
      // timestamp, so other Clients could miss the delta behind their cursor.
      // Restamping on every Host acceptance makes Local sync timing stable.
      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority = appIdentity.isHost && change.deviceId != _deviceId;
      final incomingMeta = _syncV2MetaOf(change);
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? _newSyncEnvelopeId(acceptedAt, 'evt')
          : (_syncMetaString(change, 'eventId').isNotEmpty ? _syncMetaString(change, 'eventId') : change.id);
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
      if (shouldMirrorToCloud) {
        _enqueueSyncChangeForTarget(storedChange.id, 'cloud', acceptedAt);
      }
      existingIds.add(change.id);
      existingIds.add(storedChange.id);
      final storedEventId = _syncMetaString(storedChange, 'eventId');
      if (storedEventId.isNotEmpty) existingEventIds.add(storedEventId);
      final storedSourceCommandId = _syncMetaString(storedChange, 'sourceCommandId');
      if (storedSourceCommandId.isNotEmpty) acceptedSourceCommandIds.add(storedSourceCommandId);
      changed = true;
    }
    if (changed) {
      _ensureCatalogDefaults();
      _normalizeCustomers();
      if (saveAllBusinessData) {
        await _saveAll();
      } else {
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
            sync: true,
          ),
        ]);
      }
      notifyListeners();
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
      final ids = grouped.map(idOf).where((id) => id.trim().isNotEmpty).toSet().toList();
      if (ids.length > 1) {
        output.add(DataConflict(
          entityType: entityType,
          keyName: keyName,
          keyValue: display[key] ?? key,
          recordIds: ids,
          blocking: blocking,
          message: message,
        ));
      }
    });
  }

  List<DataConflict> _detectDataConflicts() {
    final result = <DataConflict>[];
    _addDuplicateConflicts<Customer>(
      result,
      _customers.where((item) => !item.isDeleted && item.id != walkInCustomerId),
      'Customers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message: 'Created offline on more than one device. Keep both records and review manually.',
    );
    _addDuplicateConflicts<Supplier>(
      result,
      _suppliers.where((item) => !item.isDeleted),
      'Suppliers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message: 'Supplier names are duplicated after sync. Review manually; records were not merged.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where((item) => !item.isDeleted),
      'Products',
      'code',
      (item) => item.code,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate product codes can affect search, sales, stock, and reports.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where((item) => !item.isDeleted && item.barcode.trim().isNotEmpty),
      'Products',
      'barcode',
      (item) => item.barcode,
      (item) => item.id,
      blocking: true,
      message: 'Barcode is ambiguous. Avoid barcode sales until one product barcode is changed.',
    );
    _addDuplicateConflicts<CatalogItem>(result, _categories.where((item) => !item.isDeleted), 'Categories', 'English name', (item) => item.nameEn, (item) => item.id);
    _addDuplicateConflicts<CatalogItem>(result, _categories.where((item) => !item.isDeleted), 'Categories', 'Arabic name', (item) => item.nameAr, (item) => item.id);
    _addDuplicateConflicts<CatalogItem>(result, _brands.where((item) => !item.isDeleted), 'Brands', 'English name', (item) => item.nameEn, (item) => item.id);
    _addDuplicateConflicts<CatalogItem>(result, _brands.where((item) => !item.isDeleted), 'Brands', 'Arabic name', (item) => item.nameAr, (item) => item.id);
    _addDuplicateConflicts<CatalogItem>(result, _units.where((item) => !item.isDeleted), 'Units', 'English name', (item) => item.nameEn, (item) => item.id);
    _addDuplicateConflicts<CatalogItem>(result, _units.where((item) => !item.isDeleted), 'Units', 'Arabic name', (item) => item.nameAr, (item) => item.id);
    _addDuplicateConflicts<AppUser>(
      result,
      _users,
      'Users',
      'username',
      (item) => item.username,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate usernames are a security conflict. Rename or disable one user before relying on login.',
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
      message: 'A product should have only one active price per supplier. Merge or delete the duplicate record.',
    );
    _addDuplicateConflicts<Sale>(
      result,
      _sales.where((item) => !item.isDeleted),
      'Sales',
      'invoice number',
      (item) => item.invoiceNo,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate invoice numbers must be reviewed before printing/exporting final reports.',
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
      final incomingDevice = (incoming.lastModifiedByDeviceId as String?) ?? (incoming.deviceId as String?) ?? '';
      final localDevice = (local.lastModifiedByDeviceId as String?) ?? (local.deviceId as String?) ?? '';
      return incomingDevice.compareTo(localDevice) >= 0;
    } catch (_) {
      return true;
    }
  }

  void _upsertByUpdatedAt<T>(List<T> list, T incoming, String Function(T item) idOf) {
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
        final sameProductSupplier = item.productId == normalized.productId && item.supplierId == normalized.supplierId;
        if (!sameProductSupplier) continue;
        if (_remoteWins(normalized, item)) {
          _supplierProductPrices[i] = item.copyWith(
            deletedAt: normalized.updatedAt,
            updatedAt: normalized.updatedAt,
            syncStatus: 'synced',
            notes: [item.notes, 'Merged duplicate supplier price from sync'].where((part) => part.trim().isNotEmpty).join(' — '),
          );
        } else {
          return;
        }
      }
    }
    if (normalized.isPreferred && !normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted && item.productId == normalized.productId && item.id != normalized.id && item.isPreferred) {
          _supplierProductPrices[i] = item.copyWith(
            isPreferred: false,
            updatedAt: normalized.updatedAt.isAfter(item.updatedAt) ? normalized.updatedAt : item.updatedAt,
            syncStatus: 'synced',
          );
        }
      }
    }
    _upsertByUpdatedAt<SupplierProductPrice>(_supplierProductPrices, normalized, (item) => item.id);
  }

  Future<void> _applySyncChangePayload(SyncChange change) async {
    final p = change.payload;
    switch (change.entityType) {
      case 'system':
        if (change.operation == 'reset_store_data') {
          _syncChanges.clear();
          _syncQueue.clear();
          final nextEpoch = change.storeEpoch > appIdentity.storeEpoch ? change.storeEpoch : appIdentity.storeEpoch + 1;
          _appIdentity = appIdentity.copyWith(storeEpoch: nextEpoch, updatedAt: DateTime.now());
          await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
          _resetBusinessDataInMemory(keepStoreProfile: p['keepStoreProfile'] as bool? ?? true);
        } else if (change.operation == 'restore_snapshot') {
          // A cloud/LAN bootstrap snapshot contains the Host identity. Never let
          // a Client import that identity or it may start behaving as the Host.
          await _replaceFromBackupMap(p, preserveLocalIdentityForLanClient: true);
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
            await LocalDatabaseService.setString(_hostTransferRequestKey, jsonEncode(p));
          }
        } else if (change.operation == 'approve') {
          final approvedDeviceId = p['approvedDeviceId']?.toString().trim() ?? '';
          if (approvedDeviceId == _deviceId) {
            await LocalDatabaseService.setString(_hostTransferApprovedDeviceKey, approvedDeviceId);
          }
        } else if (change.operation == 'new_host_activated' || change.operation == 'HOST_CHANGED' || change.operation == 'notify_clients_host_changed') {
          final newHostDeviceId = p['newHostDeviceId']?.toString().trim() ?? '';
          final oldHostDeviceId = p['oldHostDeviceId']?.toString().trim() ?? '';
          final shouldSwitchToNewHost = newHostDeviceId.isNotEmpty &&
              newHostDeviceId != _deviceId &&
              (appIdentity.isClient || (appIdentity.isHost && oldHostDeviceId == _deviceId));
          if (shouldSwitchToNewHost) {
            await _forceApplyRoleFromTransfer(appIdentity.copyWith(
              deviceRole: DeviceRole.client,
              hostDeviceId: newHostDeviceId,
              updatedAt: DateTime.now(),
            ));
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
        break;
      case 'app_identity':
        if (change.entityId == _deviceId) {
          final incomingIdentity = _normalizedLocalIdentity(AppIdentity.fromJson(p));
          _assertSafeRoleTransition(incomingIdentity, source: 'remote app identity change');
          _appIdentity = incomingIdentity;
          await LocalDatabaseService.setString(_appIdentityKey, jsonEncode(_appIdentity!.toJson()));
        }
        break;
      case 'role':
        if (change.operation == 'delete') {
          _roles.removeWhere((item) => item.id == change.entityId && !item.isSystem);
        } else {
          _upsertByUpdatedAt<UserRole>(_roles, UserRole.fromJson(p), (item) => item.id);
        }
        break;
      case 'user':
        if (change.operation == 'delete') {
          _users.removeWhere((item) => item.id == change.entityId && !item.isSystem);
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
          _upsertByUpdatedAt<Product>(_products, Product.fromJson(p), (item) => item.id);
        }
        break;
      case 'customer':
        if (change.operation == 'delete' && p.isEmpty) {
          _customers.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Customer>(_customers, Customer.fromJson(p), (item) => item.id);
        }
        break;
      case 'supplier':
        if (change.operation == 'delete' && p.isEmpty) {
          _suppliers.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Supplier>(_suppliers, Supplier.fromJson(p), (item) => item.id);
        }
        break;
      case 'supplier_product_price':
        if (change.operation == 'delete' && p.isEmpty) {
          _supplierProductPrices.removeWhere((item) => item.id == change.entityId);
        } else {
          _applySupplierProductPriceFromSync(SupplierProductPrice.fromJson(p));
        }
        break;
      case 'expense':
        if (change.operation == 'delete' && p.isEmpty) {
          _expenses.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Expense>(_expenses, Expense.fromJson(p), (item) => item.id);
        }
        break;
      case 'category':
        if (change.operation == 'delete' && p.isEmpty) {
          _categories.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(_categories, CatalogItem.fromJson(p), (item) => item.id);
        }
        break;
      case 'brand':
        if (change.operation == 'delete' && p.isEmpty) {
          _brands.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(_brands, CatalogItem.fromJson(p), (item) => item.id);
        }
        break;
      case 'unit':
        if (change.operation == 'delete' && p.isEmpty) {
          _units.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(_units, CatalogItem.fromJson(p), (item) => item.id);
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
          _upsertByUpdatedAt<SaleQuotation>(_saleQuotations, SaleQuotation.fromJson(p), (item) => item.id);
        }
        break;
      case 'delivery_note':
        if (change.operation == 'delete' && p.isEmpty) {
          _deliveryNotes.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<DeliveryNote>(_deliveryNotes, DeliveryNote.fromJson(p), (item) => item.id);
        }
        break;
      case 'bill_of_materials':
        if (change.operation == 'delete' && p.isEmpty) {
          _billsOfMaterials.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<BillOfMaterials>(_billsOfMaterials, BillOfMaterials.fromJson(p), (item) => item.id);
        }
        break;
      case 'manufacturing_order':
        if (change.operation == 'delete' && p.isEmpty) {
          _manufacturingOrders.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<ManufacturingOrder>(_manufacturingOrders, ManufacturingOrder.fromJson(p), (item) => item.id);
        }
        break;
      case 'purchase':
        final incomingPurchase = Purchase.fromJson(p);
        _upsertByUpdatedAt<Purchase>(_purchases, incomingPurchase, (item) => item.id);
        break;
      case 'account_transaction':
        if (change.operation == 'delete' && p.isEmpty) {
          _accountTransactions.removeWhere((item) => item.id == change.entityId);
          _invalidateAccountLedgerCache();
        } else {
          _upsertByUpdatedAt<AccountTransaction>(_accountTransactions, AccountTransaction.fromJson(p), (item) => item.id);
          _invalidateAccountLedgerCache();
        }
        break;
      case 'stock_movement':
        final movement = StockMovement.fromJson(p);
        if (_stockMovements.any((item) => item.id == movement.id)) break;
        _stockMovements.add(movement.copyWith(syncStatus: 'synced'));
        final productId = movement.productId;
        final quantity = movement.quantity;
        final index = _products.indexWhere((item) => item.id == productId);
        if (index != -1 && quantity != 0) {
          final product = _products[index];
          if (!product.trackStock) break;
          final at = movement.date;
          _products[index] = product.copyWith(
            stock: product.stock + quantity,
            cost: movement.type == 'purchase_receive' && movement.unitCost > 0 ? movement.unitCost : product.cost,
            usdCost: movement.type == 'purchase_receive' && movement.unitCost > 0 ? movement.unitCost : product.usdCost,
            updatedAt: at.isAfter(product.updatedAt) ? at : product.updatedAt,
            syncStatus: 'synced',
          );
        }
        break;
    }
  }



  String? _remoteSyncChangeApplyProblem(SyncChange change) {
    if (change.entityType == 'system') return null;

    bool exists<T>(Iterable<T> items, String Function(T item) idOf) => items.any((item) => idOf(item) == change.entityId);
    final deleteWithEmptyPayload = change.operation == 'delete' && change.payload.isEmpty;

    switch (change.entityType) {
      case 'store_profile':
        return null;
      case 'app_identity':
        return null;
      case 'role':
        return deleteWithEmptyPayload || exists<UserRole>(_roles, (item) => item.id) ? null : 'role ${change.entityId} was not stored locally';
      case 'user':
        return deleteWithEmptyPayload || exists<AppUser>(_users, (item) => item.id) ? null : 'user ${change.entityId} was not stored locally';
      case 'product':
        return deleteWithEmptyPayload || exists<Product>(_products, (item) => item.id) ? null : 'product ${change.entityId} was not stored locally';
      case 'customer':
        return deleteWithEmptyPayload || exists<Customer>(_customers, (item) => item.id) ? null : 'customer ${change.entityId} was not stored locally';
      case 'supplier':
        return deleteWithEmptyPayload || exists<Supplier>(_suppliers, (item) => item.id) ? null : 'supplier ${change.entityId} was not stored locally';
      case 'supplier_product_price':
        return deleteWithEmptyPayload || exists<SupplierProductPrice>(_supplierProductPrices, (item) => item.id) ? null : 'supplier product price ${change.entityId} was not stored locally';
      case 'expense':
        return deleteWithEmptyPayload || exists<Expense>(_expenses, (item) => item.id) ? null : 'expense ${change.entityId} was not stored locally';
      case 'category':
        return deleteWithEmptyPayload || exists<CatalogItem>(_categories, (item) => item.id) ? null : 'category ${change.entityId} was not stored locally';
      case 'brand':
        return deleteWithEmptyPayload || exists<CatalogItem>(_brands, (item) => item.id) ? null : 'brand ${change.entityId} was not stored locally';
      case 'unit':
        return deleteWithEmptyPayload || exists<CatalogItem>(_units, (item) => item.id) ? null : 'unit ${change.entityId} was not stored locally';
      case 'sale':
        return deleteWithEmptyPayload || exists<Sale>(_sales, (item) => item.id) ? null : 'sale ${change.entityId} was not stored locally';
      case 'sale_quotation':
        return deleteWithEmptyPayload || exists<SaleQuotation>(_saleQuotations, (item) => item.id) ? null : 'sale quotation ${change.entityId} was not stored locally';
      case 'delivery_note':
        return deleteWithEmptyPayload || exists<DeliveryNote>(_deliveryNotes, (item) => item.id) ? null : 'delivery note ${change.entityId} was not stored locally';
      case 'bill_of_materials':
        return deleteWithEmptyPayload || exists<BillOfMaterials>(_billsOfMaterials, (item) => item.id) ? null : 'BOM ${change.entityId} was not stored locally';
      case 'manufacturing_order':
        return deleteWithEmptyPayload || exists<ManufacturingOrder>(_manufacturingOrders, (item) => item.id) ? null : 'manufacturing order ${change.entityId} was not stored locally';
      case 'purchase':
        return deleteWithEmptyPayload || exists<Purchase>(_purchases, (item) => item.id) ? null : 'purchase ${change.entityId} was not stored locally';
      case 'account_transaction':
        return deleteWithEmptyPayload || exists<AccountTransaction>(_accountTransactions, (item) => item.id) ? null : 'account transaction ${change.entityId} was not stored locally';
      case 'stock_movement':
        return exists<StockMovement>(_stockMovements, (item) => item.id) ? null : 'stock movement ${change.entityId} was not stored locally';
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
      throw StateError('Remote sync apply verification failed: ${problems.take(5).join('; ')}');
    }
  }


  Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) && item.status != 'synced' && item.status != 'rejected') {
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
      if (idSet.contains(item.changeId) || matchedChangeIds.contains(item.changeId)) {
        _syncQueue[i] = item.copyWith(status: 'synced', updatedAt: now, clearNextRetryAt: true);
      }
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncQueueChangesInProgress(Iterable<String> changeIds) async {
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) && _syncQueue[i].status != 'synced') {
        _syncQueue[i] = _syncQueue[i].copyWith(status: 'inProgress', updatedAt: now, clearNextRetryAt: true);
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncChangesRejectedByIds(Map<String, String> rejected) async {
    if (rejected.isEmpty) return;
    final idSet = rejected.keys.toSet();
    final now = DateTime.now();
    var changed = false;
    final rejectedChanges = <SyncChange>[];
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      final reason = rejected[item.changeId];
      if (idSet.contains(item.changeId) && item.status != 'synced' && reason != null) {
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
      quarantinedLocalCreate = _quarantineRejectedLocalCreates(rejectedChanges, rejected, now);
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

  bool _quarantineRejectedLocalCreates(List<SyncChange> rejectedChanges, Map<String, String> rejectedReasons, DateTime now) {
    var changed = false;
    for (final change in rejectedChanges) {
      // Only quarantine local creates/drafts. Remote authoritative changes must
      // never be deleted because of a status poll. The most common rejection in
      // the stress tests is duplicate product code/barcode; leaving that local
      // draft visible makes device counts diverge even though the Host rejected it.
      if (change.deviceId != _deviceId || change.operation == 'delete') continue;
      final reason = rejectedReasons[change.id] ??
          rejectedReasons[_syncMetaString(change, 'eventId')] ??
          rejectedReasons[_syncMetaString(change, 'requestId')] ??
          rejectedReasons[_syncMetaString(change, 'sourceCommandId')] ??
          'Rejected by Host.';
      switch (change.entityType) {
        case 'product':
          final index = _products.indexWhere((item) => item.id == change.entityId && !item.isDeleted);
          if (index >= 0) {
            _products[index] = _products[index].copyWith(
              isActive: false,
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(_productsKey, _products[index].toJson());
            changed = true;
          }
          break;
        case 'customer':
          final index = _customers.indexWhere((item) => item.id == change.entityId && !item.isDeleted);
          if (index >= 0) {
            _customers[index] = _customers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(_customersKey, _customers[index].toJson());
            changed = true;
          }
          break;
        case 'supplier':
          final index = _suppliers.indexWhere((item) => item.id == change.entityId && !item.isDeleted);
          if (index >= 0) {
            _suppliers[index] = _suppliers[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(_suppliersKey, _suppliers[index].toJson());
            changed = true;
          }
          break;
        case 'supplier_product_price':
          final index = _supplierProductPrices.indexWhere((item) => item.id == change.entityId && !item.isDeleted);
          if (index >= 0) {
            _supplierProductPrices[index] = _supplierProductPrices[index].copyWith(
              syncStatus: 'rejected: $reason',
              updatedAt: now,
              deletedAt: now,
            );
            _rememberSqliteDirtyBusinessRow(_supplierProductPricesKey, _supplierProductPrices[index].toJson());
            changed = true;
          }
          break;
      }
    }
    return changed;
  }

  Future<void> markSyncQueueChangesFailed(Iterable<String> changeIds, String error) async {
    final idSet = changeIds.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      if (idSet.contains(_syncQueue[i].changeId) && _syncQueue[i].status != 'synced') {
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
      if (item.status == 'failed' && (target == null || item.target == target)) {
        _syncQueue[i] = item.copyWith(status: 'pending', updatedAt: now, clearNextRetryAt: true);
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> recoverStaleInProgressSyncQueue({String? target, Duration staleAfter = const Duration(seconds: 45)}) async {
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
          lastError: 'Recovered stale in-progress sync item after timeout/crash.',
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

  BackupSummary get currentBackupSummary => BackupSummary(
        version: 11,
        generatedAt: DateTime.now(),
        productsCount: products.length,
        customersCount: customers.length,
        salesCount: sales.length,
        suppliersCount: suppliers.length,
        expensesCount: expenses.length,
        storeName: _storeProfile.name,
      );

  BackupValidationResult validateBackupJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const BackupValidationResult(
          isValid: false,
          summary: null,
          errorMessage: 'Backup content must be a JSON object.',
        );
      }

      final map = Map<String, dynamic>.from(decoded);
      if (!map.containsKey('products') || !map.containsKey('customers') || !map.containsKey('sales')) {
        return const BackupValidationResult(
          isValid: false,
          summary: null,
          errorMessage: 'Missing required backup sections.',
        );
      }

      final products = (map['products'] as List<dynamic>? ?? const <dynamic>[]).length;
      final customers = (map['customers'] as List<dynamic>? ?? const <dynamic>[]).length;
      final sales = (map['sales'] as List<dynamic>? ?? const <dynamic>[]).length;
      final suppliers = (map['suppliers'] as List<dynamic>? ?? const <dynamic>[]).length;
      final expenses = (map['expenses'] as List<dynamic>? ?? const <dynamic>[]).length;

      DateTime? generatedAt;
      final generatedAtRaw = map['generatedAt'];
      if (generatedAtRaw is String && generatedAtRaw.trim().isNotEmpty) {
        generatedAt = DateTime.tryParse(generatedAtRaw);
      }

      final storeProfileMap = map['storeProfile'] is Map ? Map<String, dynamic>.from(map['storeProfile'] as Map) : <String, dynamic>{};
      final storeName = (storeProfileMap['name'] as String?)?.trim();

      return BackupValidationResult(
        isValid: true,
        summary: BackupSummary(
          version: (map['version'] as num?)?.toInt() ?? 0,
          generatedAt: generatedAt,
          productsCount: products,
          customersCount: customers,
          salesCount: sales,
          suppliersCount: suppliers,
          expensesCount: expenses,
          storeName: (storeName == null || storeName.isEmpty) ? 'My Store' : storeName,
        ),
      );
    } catch (_) {
      return const BackupValidationResult(
        isValid: false,
        summary: null,
        errorMessage: 'Invalid or corrupted backup JSON.',
      );
    }
  }

}
