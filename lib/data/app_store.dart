// ignore_for_file: unused_element, unused_field, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart' as pc;

import '../core/services/local_database_service.dart';
import '../core/services/accounting_service.dart';
import '../core/services/business_revision_service.dart';
import '../core/services/password_hashing.dart';
import '../core/services/startup_timing_service.dart';
import '../core/services/sqlite_sync_state_service.dart';
import '../core/repositories/business_session_context.dart';
import '../core/repositories/business_repositories.dart';
import '../core/storage/sqlite/business_sqlite_store.dart';
import '../core/storage/sqlite/sqlite_migration_manager.dart';
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
import '../models/product_costing.dart';
import '../models/purchase.dart';
import '../models/supplier_product_price.dart';
import '../models/stock_movement.dart';
import '../models/sale.dart';
import '../models/sale_quotation.dart';
import '../models/store_profile.dart';
import '../models/supplier.dart';
import '../models/sync_change.dart';
import '../models/sync_queue_item.dart';
import '../models/user_role.dart';
import '../models/app_user.dart';
import '../models/app_identity.dart';

part 'app_store_backup.dart';
part 'app_store_recovery.dart';

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

class AppStore extends ChangeNotifier implements BusinessSessionContext {
  static AppStoreTraceSink? _traceSink;
  late final AppStoreRecoveryService recovery = AppStoreRecoveryService(this);
  late final SqliteSyncStateService syncState = const SqliteSyncStateService();

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
  static const _sessionPermissionsKey = 'session_permissions_v1';
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

  final List<SyncChange> _syncChanges = [];
  final List<SyncQueueItem> _syncQueue = [];
  final List<SyncChange> _sqliteDirtySyncChanges = [];
  final List<SyncQueueItem> _sqliteDirtySyncQueue = [];
  StoreProfile _storeProfile = StoreProfile.defaults;
  InventoryCostingMethod _inventoryCostingMethod =
      InventoryCostingMethod.weightedAverage;
  int _invoiceCounter = 0;
  int _purchaseCounter = 0;
  String _currentRole = 'admin'; // legacy compatibility
  final Set<String> _sessionPermissions = <String>{};
  bool _sessionIsAdmin = false;
  bool _needsInitialAdminSetup = true;
  bool _hasLocalAdminUser = false;
  String _deviceId = '';
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
  bool _heavyDataLoadCompleted = false;
  bool _ledgerDataLoadCompleted = false;
  bool _syncDataLoadCompleted = false;
  Future<void>? _syncDataLoadFuture;
  int _syncDataGeneration = 0;

  bool get isReady => _isReady;
  bool get isCoreDataLoaded => _isReady;
  bool get isLedgerDataLoaded => _isReady;
  bool get needsInitialAdminSetup => _needsInitialAdminSetup;
  bool get hasLocalAdminUser => _hasLocalAdminUser;

  bool get isSyncDataLoaded => _syncDataLoadCompleted;
  bool get isHeavyDataLoaded =>
      _heavyDataLoadCompleted &&
      _ledgerDataLoadCompleted &&
      _syncDataLoadCompleted;

  Future<void> applySessionUser({
    required AppUser? activeUser,
    required String currentRole,
    required Set<String> permissions,
    required bool rememberLogin,
  }) async {
    _activeUser = activeUser;
    _rememberLogin = rememberLogin;
    _currentRole = currentRole.trim().isEmpty ? 'admin' : currentRole.trim();
    _sessionPermissions
      ..clear()
      ..addAll(permissions);
    _sessionIsAdmin =
        activeUser?.roleId == 'admin' || permissions.contains('*');
    await LocalDatabaseService.setString(
      _activeUserKey,
      rememberLogin && activeUser != null ? activeUser.id : '',
    );
    await LocalDatabaseService.setString(
      _rememberLoginKey,
      rememberLogin ? 'true' : 'false',
    );
    await LocalDatabaseService.setString(_currentRoleKey, _currentRole);
    await LocalDatabaseService.setString(
      _sessionPermissionsKey,
      jsonEncode(_sessionPermissions.toList(growable: false)..sort()),
    );
    notifyListeners();
  }

  Future<void> clearSessionUser() async {
    await applySessionUser(
      activeUser: null,
      currentRole: 'admin',
      permissions: const <String>{},
      rememberLogin: false,
    );
    await LocalDatabaseService.setString(_sessionPermissionsKey, '[]');
  }

  Future<void> _refreshAuthFlags() async {
    final users = await UserRepository.listAll();
    _hasLocalAdminUser =
        users.any((user) => user.roleId == 'admin' && user.isActive);
    if (users.isEmpty) {
      _needsInitialAdminSetup = true;
      return;
    }
    if (users.length != 1) {
      _needsInitialAdminSetup = false;
      return;
    }
    final user = users.first;
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
    _needsInitialAdminSetup = user.id == 'admin' &&
        user.username.trim().toLowerCase() == 'admin' &&
        user.lastLoginAt == null &&
        await PasswordHashing.verifyPassword(legacyPassword, user.passwordHash);
  }

  Future<void> warmDeferredPageCaches() async {
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;
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

  Future<void> ensureHeavyDataLoaded() async {
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;
    await _requestSyncDataLoad();
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
    return List<SyncQueueItem>.unmodifiable(
      _syncQueue.toList(growable: false),
    );
  }

  List<SyncChange> get pendingSyncChanges {
    _requestSyncDataLoad();
    return List<SyncChange>.unmodifiable(
      _syncChanges.where((item) => !item.isSynced).toList(growable: false),
    );
  }

  @override
  InventoryCostingMethod get inventoryCostingMethod => _inventoryCostingMethod;

  @override
  String get deviceId => _deviceId;
  int get pendingSyncCount {
    _requestSyncDataLoad();
    return _syncQueue.where((item) => item.isPending).length;
  }

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
    return _syncQueue
        .where((item) => item.target == target && item.status != 'synced')
        .length;
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

  @override
  StoreProfile get storeProfile => _storeProfile;
  @override
  String get currentRole => _currentRole;
  @override
  AppUser? get activeUser => _activeUser;
  bool get rememberLogin => _rememberLogin;
  AppUser? get currentUser => _activeUser;
  @override
  AppIdentity get appIdentity =>
      _appIdentity ??
      AppIdentity.defaults(deviceId: _deviceId, platform: _detectPlatform());
  bool get isAdmin => _sessionIsAdmin || _activeUser?.roleId == 'admin';
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

  @override
  bool hasPermission(String permission) {
    if (_activeUser == null) return false;
    if (_sessionIsAdmin) return true;
    return _sessionPermissions.contains(permission);
  }

  @override
  void requirePermission(String permission) {
    if (!hasPermission(permission)) {
      throw StateError('You do not have permission: $permission');
    }
  }

  void refreshUi() {
    notifyListeners();
  }

  Future<void> initialize() async {
    StartupTimingService.event('app_store.initialize.begin',
        category: 'app_store');
    await _ensureDeviceId();
    _storeProfile = _loadStoreProfile();
    AccountingService.configureMoneyPolicy(_storeProfile);
    _invoiceCounter = _loadInvoiceCounter();
    _purchaseCounter = _loadPurchaseCounter();
    _currentRole = LocalDatabaseService.getString(_currentRoleKey) ?? 'admin';
    _rememberLogin =
        LocalDatabaseService.getString(_rememberLoginKey) == 'true';
    _appIdentity = _loadOrCreateAppIdentity();
    _syncSequence = _loadSyncSequence();
    await _loadSessionPermissionsFromStorage();
    await _restoreActiveUserFromStorage();
    await _refreshAuthFlags();
    await ProductRepository.ensureDefaultPriceLists();
    _heavyDataLoadCompleted = true;
    _ledgerDataLoadCompleted = true;
    _syncDataLoadCompleted = true;

    _isReady = true;
    notifyListeners();
    unawaited(_requestSyncDataLoad());
    StartupTimingService.event('app_store.ready', category: 'app_store');
  }

  Future<void> _loadSessionPermissionsFromStorage() async {
    final raw = LocalDatabaseService.getString(_sessionPermissionsKey);
    if (raw == null || raw.trim().isEmpty) {
      _sessionPermissions.clear();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _sessionPermissions
          ..clear()
          ..addAll(
            decoded
                .whereType<String>()
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty),
          );
        return;
      }
    } catch (_) {}
    _sessionPermissions.clear();
  }

  Future<void> _restoreActiveUserFromStorage() async {
    if (isSuspendedByHost) {
      _activeUser = null;
      _rememberLogin = false;
      return;
    }
    if (!_rememberLogin) {
      _activeUser = null;
      return;
    }
    final activeId =
        LocalDatabaseService.getString(_activeUserKey)?.trim() ?? '';
    if (activeId.isEmpty) {
      _activeUser = null;
      return;
    }
    final user = await UserRepository.getById(activeId);
    if (user == null || !user.isActive) {
      _activeUser = null;
      return;
    }
    _activeUser = user;
    _sessionIsAdmin =
        user.roleId == 'admin' || _sessionPermissions.contains('*');
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

  Future<void> _loadDeferredStartupData() async {
    _heavyDataLoadCompleted = true;
  }

  Future<void> _loadLedgerDeferredStartupData() async {
    _ledgerDataLoadCompleted = true;
  }

  Future<void> _loadSyncDeferredStartupData() async {
    try {
      final loadGeneration = _syncDataGeneration;
      await StartupTimingService.measure(
        'app_store.sync_deferred_startup',
        () async {
          await Future<void>.delayed(Duration.zero);
          final syncChanges = await _decodeDeferredList<SyncChange>(
            _syncChangesKey,
            SyncChange.fromJson,
            batchSize: 100,
          );
          if (loadGeneration != _syncDataGeneration) return;
          if (_syncChanges.isEmpty) {
            _syncChanges
              ..clear()
              ..addAll(syncChanges);
          } else if (syncChanges.isNotEmpty) {
            final mergedChanges = <String, SyncChange>{
              for (final item in _syncChanges) item.id: item,
            };
            for (final item in syncChanges) {
              mergedChanges.putIfAbsent(item.id, () => item);
            }
            _syncChanges
              ..clear()
              ..addAll(mergedChanges.values);
          }
          await Future<void>.delayed(Duration.zero);

          final syncQueue = await _decodeDeferredList<SyncQueueItem>(
            _syncQueueKey,
            SyncQueueItem.fromJson,
            batchSize: 100,
          );
          if (loadGeneration != _syncDataGeneration) return;
          if (_syncQueue.isEmpty) {
            _syncQueue
              ..clear()
              ..addAll(syncQueue);
          } else if (syncQueue.isNotEmpty) {
            final mergedQueue = <String, SyncQueueItem>{
              for (final item in _syncQueue) item.id: item,
            };
            for (final item in syncQueue) {
              mergedQueue.putIfAbsent(item.id, () => item);
            }
            _syncQueue
              ..clear()
              ..addAll(mergedQueue.values);
          }
          notifyListeners();
        },
        category: 'app_store',
      );
    } catch (error, stackTrace) {
      debugPrint('Sync startup data load failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void _touchBusinessRevisionsForDatabaseKey(String key) {
    BusinessRevisionService.instance.touchForKey(key);
  }

  /// Reloads the lightweight AppStore state after a database admin change.
  @override
  Future<void> refreshAfterDatabaseChange(String key) async {
    try {
      switch (key) {
        case _appIdentityKey:
          _appIdentity = _loadOrCreateAppIdentity();
          break;
        case _storeProfileKey:
          _storeProfile = _loadStoreProfile();
          AccountingService.configureMoneyPolicy(_storeProfile);
          BusinessRevisionService.instance.touchForKey(_storeProfileKey);
          break;
        case _rolesKey:
        case _usersKey:
        case _activeUserKey:
        case _rememberLoginKey:
          _rememberLogin =
              LocalDatabaseService.getString(_rememberLoginKey) == 'true';
          await _loadSessionPermissionsFromStorage();
          await _restoreActiveUserFromStorage();
          await _refreshAuthFlags();
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
          BusinessRevisionService.instance.touchSyncSequence();
          break;
        case _inventoryCostingMethodKey:
          _inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
            LocalDatabaseService.getString(_inventoryCostingMethodKey),
          );
          break;
        case _costingMethodHistoryKey:
          break;
        default:
          _touchBusinessRevisionsForDatabaseKey(key);
          break;
      }
      _invalidateDerivedDataCaches();
      refreshUi();
    } catch (error, stackTrace) {
      debugPrint('Database admin refresh failed for $key: $error');
      debugPrint('$stackTrace');
      await reloadAllAfterDatabaseChange();
    }
  }

  /// Conservative lightweight refresh used for unknown keys or recovery after a failed targeted refresh.
  Future<void> reloadAllAfterDatabaseChange() async {
    await StartupTimingService.measure(
      'app_store.reload_metadata_only_sqlite',
      () async {
        _appIdentity = _loadOrCreateAppIdentity();
        _storeProfile = _loadStoreProfile();
        AccountingService.configureMoneyPolicy(_storeProfile);
        _rememberLogin =
            LocalDatabaseService.getString(_rememberLoginKey) == 'true';
        await _loadSessionPermissionsFromStorage();
        await _restoreActiveUserFromStorage();
        await _refreshAuthFlags();
        _inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
          LocalDatabaseService.getString(_inventoryCostingMethodKey),
        );
        _invoiceCounter = _loadInvoiceCounter();
        _purchaseCounter = _loadPurchaseCounter();
        _syncSequence = _loadSyncSequence();
        BusinessRevisionService.instance.touchAll();
        refreshUi();
      },
      category: 'app_store',
    );
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
    // Catalog defaults are owned by SQLite repositories now.
  }

  Future<void> _persistCatalogDefaultsIfMissing() async {
    // Catalog defaults are owned by SQLite repositories now.
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

  int _readVersion(dynamic value) {
    try {
      final raw = value.version;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? 0;
    } catch (_) {}
    try {
      final raw = value['version'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? 0;
    } catch (_) {}
    return 0;
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
    return int.tryParse(raw ?? '') ?? 0;
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

  Future<void> clearLocalHostTransferRequest() async {
    await LocalDatabaseService.setString(_hostTransferRequestKey, '');
    notifyListeners();
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

  void _normalizeCustomers() {}

  Future<void> _persistProductDerivedData() async {}

  void _markProductDerivedDataDirty() {}

  Future<void> _flushProductDerivedData() async {}

  void _rebuildProductIndexes() {}

  void _rebuildCustomerIndexes() {}

  void _rebuildSupplierIndexes() {}

  void _rebuildMutableEntityIndexes() {}

  void _rebuildStockMovementIndexes() {}

  int _stockMovementIndexForId(String id) => -1;

  void _rebuildPurchaseIndexes() {}

  int _purchaseIndexForId(String id) => -1;

  void _putStockMovementAtIndex(StockMovement movement, int index) {}

  void _rebuildExpenseIndexes() {}

  void _rebuildAccountTransactionIndexes() {}

  int _expenseIndexForId(String id) => -1;

  int _accountTransactionIndexForId(String id) => -1;

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
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
  }) {
    if (storeProfile) {
      BusinessRevisionService.instance.touchForKey(_storeProfileKey);
    }
  }

  void _touchPurchasesData() {}

  void _touchExpensesData() {}

  void _removePurchaseAtIndex(int index) {
    // Legacy in-memory purchase cache removed.
  }

  void _putAccountTransactionAtIndex(
      AccountTransaction transaction, int index) {
    // Legacy in-memory account transaction cache removed.
  }

  void _removeExpenseAtIndex(int index) {
    // Legacy in-memory expense cache removed.
  }

  void _removeAccountTransactionAtIndex(int index) {
    // Legacy in-memory account transaction cache removed.
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
    _syncDataGeneration++;
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

  Future<void> _persistCurrentBusinessStateDirectToSqlite() async {
    await Future.wait([
      LocalDatabaseService.setString(_deviceIdKey, _deviceId),
      LocalDatabaseService.setString(
        _storeProfileKey,
        jsonEncode(_storeProfile.toJson()),
      ),
      LocalDatabaseService.setString(
        _inventoryCostingMethodKey,
        _inventoryCostingMethod.code,
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
    await _saveSyncStateOnly();
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
    bool warehouses = false,
    bool accountTransactions = false,
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
  }) async {
    _touchDataRevisions(storeProfile: storeProfile);
    if (LocalDatabaseService.isSqliteAuthoritative) {
      await _traceAsync(
        'saveDirty',
        'sqlite_hot_path',
        () => _saveDirtySqliteHotPath(
          storeProfile: storeProfile,
          invoiceCounter: invoiceCounter,
          purchaseCounter: purchaseCounter,
          sync: sync,
          productDerivedData: productDerivedData,
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
    if (sync) {}
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
      writes.add(_saveSyncStateOnly());
    }
    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

  Future<void> _saveDirtySqliteHotPath({
    bool storeProfile = false,
    bool invoiceCounter = false,
    bool purchaseCounter = false,
    bool sync = false,
    bool productDerivedData = true,
  }) async {
    final writes = <Future<void>>[];

    if (storeProfile) {
      writes.add(
        LocalDatabaseService.setString(
          _storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        ),
      );
    }
    if (productDerivedData) {
      _markProductDerivedDataDirty();
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
      writes.add(_saveSyncStateOnly());
    }

    if (writes.isEmpty) return;
    await Future.wait(writes);
  }

  Product? _findProductById(String id) {
    return null;
  }

  // Default import-section selector for internal full-replace/reset paths.
  // The manual Backup Import flow defines a local `wants` function that
  // shadows this method and uses the user-selected section IDs.
  bool wants(String id) => true;

  Product? findProductByCode(String code) {
    return null;
  }

  void _resetBusinessDataInMemory({bool keepStoreProfile = true}) {
    _invoiceCounter = 0;
    _purchaseCounter = 0;
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
    await LocalDatabaseService.clearAll();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile);
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('cloud_last_pull_cursor');
    }
    await _persistCurrentBusinessStateDirectToSqlite();
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
    await _persistCurrentBusinessStateDirectToSqlite();
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
    _syncChanges.clear();
    _syncQueue.clear();
    _invoiceCounter = 0;
    _purchaseCounter = 0;
    _storeProfile = StoreProfile.defaults;
    AccountingService.configureMoneyPolicy(_storeProfile);
    _activeUser = null;
    _rememberLogin = false;
    await LocalDatabaseService.clearAll();
    _deviceId = _generatePrefixedId('DV');
    _appIdentity = AppIdentity.defaults(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    ).copyWith(deviceRole: DeviceRole.standalone, syncMode: SyncMode.localOnly);
    BusinessRevisionService.instance.reset();
    await LocalDatabaseService.clearAll();
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
    await LocalDatabaseService.setString(
      _appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    await LocalDatabaseService.setString(_activeUserKey, '');
    await LocalDatabaseService.setString(_rememberLoginKey, 'false');
    await LocalDatabaseService.setString(
      _storeProfileKey,
      jsonEncode(_storeProfile.toJson()),
    );
    await LocalDatabaseService.setString(
      _inventoryCostingMethodKey,
      _inventoryCostingMethod.code,
    );
    await LocalDatabaseService.setString(_invoiceCounterKey, '0');
    await LocalDatabaseService.setString(_purchaseCounterKey, '0');
    await LocalDatabaseService.setString(_syncSequenceKey, '0');
    await _saveSyncStateOnly();
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
    bool expired(DateTime? deletedAt) =>
        deletedAt != null && deletedAt.isBefore(cutoff);

    final products = await ProductRepository.listAll();
    final customers = await CustomerRepository.listAll();
    final suppliers = await SupplierRepository.listAll();
    final supplierProductPrices =
        await InventoryRepository.getSupplierProductPrices() ??
            const <SupplierProductPrice>[];
    final expenses = await ExpenseRepository.listAll();
    final sales = await SaleRepository.listAll();
    final purchases = await PurchaseRepository.listAll();
    final stockMovements = await StockMovementRepository.listAll();
    final categories = await InventoryRepository.getCatalogItems(
            BusinessSqliteStore.categoriesKey) ??
        const <CatalogItem>[];
    final brands = await InventoryRepository.getCatalogItems(
            BusinessSqliteStore.brandsKey) ??
        const <CatalogItem>[];
    final units = await InventoryRepository.getCatalogItems(
            BusinessSqliteStore.unitsKey) ??
        const <CatalogItem>[];

    bool hasProductReferences(String productId) {
      return sales.any(
            (sale) =>
                !sale.isDeleted &&
                sale.items.any((item) => item.productId == productId),
          ) ||
          purchases.any(
            (purchase) =>
                !purchase.isDeleted &&
                purchase.items.any((item) => item.productId == productId),
          ) ||
          stockMovements.any((movement) => movement.productId == productId);
    }

    Future<List<T>> retainActiveRows<T>(
      List<T> items,
      bool Function(T item) keep,
    ) async {
      final retained = <T>[];
      for (var index = 0; index < items.length; index += 1) {
        final item = items[index];
        if (keep(item)) retained.add(item);
        if ((index + 1) % 250 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return retained;
    }

    final remainingProducts = await retainActiveRows(products, (item) {
      return !expired(item.deletedAt) ||
          _hasPendingSyncFor('product', item.id) ||
          hasProductReferences(item.id);
    });
    final remainingCustomers = await retainActiveRows(customers, (item) {
      return item.id == 'walk_in' ||
          !expired(item.deletedAt) ||
          _hasPendingSyncFor('customer', item.id);
    });
    final remainingSuppliers = await retainActiveRows(suppliers, (item) {
      return !expired(item.deletedAt) ||
          _hasPendingSyncFor('supplier', item.id);
    });
    final remainingSupplierProductPrices =
        await retainActiveRows(supplierProductPrices, (item) {
      return !expired(item.deletedAt) ||
          _hasPendingSyncFor('supplier_product_price', item.id);
    });
    final remainingExpenses = await retainActiveRows(expenses, (item) {
      return !expired(item.deletedAt) || _hasPendingSyncFor('expense', item.id);
    });
    final remainingCategories = await retainActiveRows(categories, (item) {
      return !expired(item.deletedAt) ||
          _hasPendingSyncFor('category', item.id);
    });
    final remainingBrands = await retainActiveRows(brands, (item) {
      return !expired(item.deletedAt) || _hasPendingSyncFor('brand', item.id);
    });
    final remainingUnits = await retainActiveRows(units, (item) {
      return !expired(item.deletedAt) || _hasPendingSyncFor('unit', item.id);
    });
    final remainingSales = await retainActiveRows(sales, (item) {
      return !expired(item.deletedAt) || _hasPendingSyncFor('sale', item.id);
    });
    final remainingPurchases = await retainActiveRows(purchases, (item) {
      return !expired(item.deletedAt) ||
          _hasPendingSyncFor('purchase', item.id);
    });

    final removed = (products.length - remainingProducts.length) +
        (customers.length - remainingCustomers.length) +
        (suppliers.length - remainingSuppliers.length) +
        (supplierProductPrices.length - remainingSupplierProductPrices.length) +
        (expenses.length - remainingExpenses.length) +
        (categories.length - remainingCategories.length) +
        (brands.length - remainingBrands.length) +
        (units.length - remainingUnits.length) +
        (sales.length - remainingSales.length) +
        (purchases.length - remainingPurchases.length);

    if (removed <= 0) {
      return 0;
    }

    Future<void> replaceRows(String key, List<dynamic> rows) async {
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        key,
        rows
            .map((item) => (item as dynamic).toJson() as Map<String, dynamic>)
            .toList(growable: false),
        sortIndices: List<int?>.generate(rows.length, (index) => index),
      );
    }

    await Future.wait([
      replaceRows(BusinessSqliteStore.productsKey, remainingProducts),
      replaceRows(BusinessSqliteStore.customersKey, remainingCustomers),
      replaceRows(BusinessSqliteStore.suppliersKey, remainingSuppliers),
      replaceRows(
        BusinessSqliteStore.supplierProductPricesKey,
        remainingSupplierProductPrices,
      ),
      replaceRows(BusinessSqliteStore.expensesKey, remainingExpenses),
      replaceRows(BusinessSqliteStore.categoriesKey, remainingCategories),
      replaceRows(BusinessSqliteStore.brandsKey, remainingBrands),
      replaceRows(BusinessSqliteStore.unitsKey, remainingUnits),
      replaceRows(BusinessSqliteStore.salesKey, remainingSales),
      replaceRows(BusinessSqliteStore.purchasesKey, remainingPurchases),
    ]);

    if (remainingProducts.length != products.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.productsKey);
    }
    if (remainingCustomers.length != customers.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.customersKey);
    }
    if (remainingSuppliers.length != suppliers.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.suppliersKey);
    }
    if (remainingSupplierProductPrices.length != supplierProductPrices.length) {
      BusinessRevisionService.instance.touchForKey(
        BusinessSqliteStore.supplierProductPricesKey,
      );
    }
    if (remainingExpenses.length != expenses.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.expensesKey);
    }
    if (remainingCategories.length != categories.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.categoriesKey);
    }
    if (remainingBrands.length != brands.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.brandsKey);
    }
    if (remainingUnits.length != units.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.unitsKey);
    }
    if (remainingSales.length != sales.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.salesKey);
    }
    if (remainingPurchases.length != purchases.length) {
      BusinessRevisionService.instance
          .touchForKey(BusinessSqliteStore.purchasesKey);
    }
    await _saveSyncStateOnly();
    notifyListeners();
    return removed;
  }

  Future<BusinessDataIntegrityResult> verifyLocalBusinessDataIntegrity() async {
    final problems = <String>[];
    final products = await ProductRepository.listAll();
    final suppliers = await SupplierRepository.listAll();
    final supplierProductPrices =
        await InventoryRepository.getSupplierProductPrices() ??
            const <SupplierProductPrice>[];
    final sales = await SaleRepository.listAll();
    final purchases = await PurchaseRepository.listAll();
    final stockMovements = await StockMovementRepository.listAll();

    final productIds = <String>{};
    for (var index = 0; index < products.length; index += 1) {
      final item = products[index];
      if (!item.isDeleted) productIds.add(item.id);
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    final supplierIds = <String>{};
    for (var index = 0; index < suppliers.length; index += 1) {
      final item = suppliers[index];
      if (!item.isDeleted) supplierIds.add(item.id);
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (var index = 0; index < supplierProductPrices.length; index += 1) {
      final price = supplierProductPrices[index];
      if (price.isDeleted) continue;
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
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final activePriceKeys = <String>{};
    for (var index = 0; index < supplierProductPrices.length; index += 1) {
      final price = supplierProductPrices[index];
      if (price.isDeleted) continue;
      final key = '${price.productId}::${price.supplierId}';
      if (!activePriceKeys.add(key)) {
        problems.add(
          'Duplicate supplier price for product ${price.productId} and supplier ${price.supplierId}',
        );
      }
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (var index = 0; index < sales.length; index += 1) {
      final sale = sales[index];
      if (sale.isDeleted) continue;
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
      final movements = stockMovements
          .where(
            (movement) =>
                movement.referenceId == sale.id && movement.type == 'sale',
          )
          .toList();
      if (sale.status != 'Cancelled' && movements.length < sale.items.length) {
        problems.add('Sale ${sale.invoiceNo} is missing stock movement(s)');
      }
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (var index = 0; index < purchases.length; index += 1) {
      final purchase = purchases[index];
      if (purchase.isDeleted) continue;
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
      if ((index + 1) % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
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
    // Legacy dirty business row cache removed.
  }

  Map<String, dynamic> _businessPayloadWithoutSyncEnvelope(
    Map<String, dynamic> payload,
  ) {
    final clean = Map<String, dynamic>.from(payload);
    clean.remove('_syncV2');
    return clean;
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

  void _invalidateDerivedDataCaches() {}

  void _invalidateAccountLedgerCache() {}

  void _rebuildInventoryCostLayerLookupCache() {}

  void _ensureDefaultWarehouse() {}

  void _markSingleSupplierPerProductAsPreferred() {}

  void _ensureDefaultPriceLists() {
    // Legacy in-memory pricing cache removed.
  }

  String _productPriceLookupKey(
    String productId,
    String priceListId,
    String unitId,
  ) =>
      '$productId|$priceListId|$unitId';

  void _rebuildProductPriceLookupCache() {
    // Legacy in-memory pricing cache removed.
  }

  void _rebuildProductCostLookupCache() {
    // Legacy in-memory pricing cache removed.
  }

  void _rebuildProductPricingLookupCaches() {
    // Legacy in-memory pricing cache removed.
  }

  void _ensureProductPricingLookupCaches() {
    // Legacy in-memory pricing cache removed.
  }

  void _ensureDefaultProductPriceEntries({Product? product}) {
    // Legacy in-memory pricing cache removed.
  }

  void _ensureProductCostEntries({Product? product}) {
    // Legacy in-memory pricing cache removed.
  }

  void _ensureCostingMethodHistory() {
    // Legacy in-memory costing history cache removed.
  }

  int _loadPurchaseCounter() {
    final raw = LocalDatabaseService.getString(_purchaseCounterKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> _backupPayload({
    List<SyncChange>? changes,
    bool includeDeviceAndSyncState = true,
  }) async {
    final inventoryCounts = await InventoryRepository.getInventoryCounts() ??
        const <InventoryCountSession>[];
    Future<List<Map<String, dynamic>>> loadRows<T>(
      Future<List<T>?> Function() loader,
    ) async {
      final items = await loader() ?? List<T>.empty(growable: false);
      return items
          .map((item) => (item as dynamic).toJson() as Map<String, dynamic>)
          .toList(growable: true);
    }

    final customers = await loadRows(() => CustomerRepository.listAll());
    customers.removeWhere((row) => row['id'] == walkInCustomerId);
    customers.insert(0, walkInCustomer.toJson());
    return {
      'version': 12,
      'generatedAt': DateTime.now().toIso8601String(),
      'schemaVersion': 17,
      'backupType':
          includeDeviceAndSyncState ? 'full_device_backup' : 'business_backup',
      if (includeDeviceAndSyncState)
        'localDatabaseEntries': LocalDatabaseService.allEntries(),
      if (!includeDeviceAndSyncState) 'storeId': appIdentity.storeId,
      if (!includeDeviceAndSyncState) 'branchId': appIdentity.branchId,
      if (!includeDeviceAndSyncState) 'appVersion': 'stage2',
      if (!includeDeviceAndSyncState) 'platform': appIdentity.platform.name,
      if (!includeDeviceAndSyncState)
        'themeMode': LocalDatabaseService.getString(_themeModeKey) ?? 'system',
      'invoiceCounter': _invoiceCounter,
      'purchaseCounter': _purchaseCounter,
      'storeProfile': _storeProfile.toJson(),
      'products': await loadRows(() => ProductRepository.listAll()),
      'customers': customers,
      'sales': await loadRows(() => SaleRepository.listAll()),
      'saleQuotations': await loadRows(() => SaleRepository.getQuotations()),
      'deliveryNotes': await loadRows(() => SaleRepository.getDeliveryNotes()),
      'billsOfMaterials':
          await loadRows(() => InventoryRepository.getBillOfMaterials()),
      'manufacturingOrders':
          await loadRows(() => InventoryRepository.getManufacturingOrders()),
      'suppliers': await loadRows(() => SupplierRepository.listAll()),
      'supplierProductPrices': await loadRows(
        () => InventoryRepository.getSupplierProductPrices(),
      ),
      'categories': await loadRows(
        () => InventoryRepository.getCatalogItems(
            BusinessSqliteStore.categoriesKey),
      ),
      'brands': await loadRows(
        () =>
            InventoryRepository.getCatalogItems(BusinessSqliteStore.brandsKey),
      ),
      'units': await loadRows(
        () => InventoryRepository.getCatalogItems(BusinessSqliteStore.unitsKey),
      ),
      'expenses': await loadRows(() => ExpenseRepository.listAll()),
      'purchases': await loadRows(() => PurchaseRepository.listAll()),
      'stockMovements': await loadRows(() => StockMovementRepository.listAll()),
      'inventoryCounts': inventoryCounts.map((item) => item.toJson()).toList(),
      'warehouses': await loadRows(() => WarehouseRepository.listAll()),
      'accountTransactions':
          await loadRows(() => AccountTransactionRepository.listAll()),
      if (includeDeviceAndSyncState) 'deviceId': _deviceId,
      if (includeDeviceAndSyncState)
        'syncChanges':
            (changes ?? _syncChanges).map((item) => item.toJson()).toList(),
      if (includeDeviceAndSyncState)
        'syncQueue': _syncQueue.map((item) => item.toJson()).toList(),
      'roles': (await RoleRepository.listAll())
          .map((item) => item.toJson())
          .toList(),
      'users': (await UserRepository.listAll())
          .map((item) => item.toJson())
          .toList(),
      if (includeDeviceAndSyncState) 'appIdentity': appIdentity.toJson(),
      if (includeDeviceAndSyncState) 'storeEpoch': appIdentity.storeEpoch,
      'syncGeneratedAt': DateTime.now().toIso8601String(),
      'syncGeneratedSequence': _syncChanges.isEmpty
          ? 0
          : _syncChanges
              .map((item) => item.sequence)
              .reduce((a, b) => a > b ? a : b),
    };
  }

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

  Future<Map<String, List<dynamic>>> _unifiedSnapshotCollectionPayloads({
    Set<String>? sectionIds,
  }) async {
    final inventoryCounts = await InventoryRepository.getInventoryCounts() ??
        const <InventoryCountSession>[];
    Future<List<dynamic>> loadList<T>(
      Future<List<T>?> Function() loader,
    ) async {
      final items = await loader() ?? List<T>.empty(growable: false);
      return items
          .map((item) => (item as dynamic).toJson())
          .toList(growable: false);
    }

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
      'roles': (await RoleRepository.listAll())
          .map((item) => item.toJson())
          .toList(),
      'users': (await UserRepository.listAll())
          .map((item) => item.toJson())
          .toList(),
      'categories': await loadList(() => InventoryRepository.getCatalogItems(
          BusinessSqliteStore.categoriesKey)),
      'brands': await loadList(() =>
          InventoryRepository.getCatalogItems(BusinessSqliteStore.brandsKey)),
      'units': await loadList(() =>
          InventoryRepository.getCatalogItems(BusinessSqliteStore.unitsKey)),
      'warehouses': await loadList(() => WarehouseRepository.listAll()),
      'products': await loadList(() => ProductRepository.listAll()),
      'customers': await loadList(() => CustomerRepository.listAll()),
      'suppliers': await loadList(() => SupplierRepository.listAll()),
      'supplierProductPrices':
          await loadList(() => InventoryRepository.getSupplierProductPrices()),
      'priceLists': await loadList(() => InventoryRepository.getPriceLists()),
      'productPrices':
          await loadList(() => InventoryRepository.getProductPrices()),
      'productPriceOverrides':
          await loadList(() => InventoryRepository.getProductPriceOverrides()),
      'productCosts':
          await loadList(() => InventoryRepository.getProductCosts()),
      'costingMethodHistory':
          await loadList(() => InventoryRepository.getCostingMethodHistory()),
      'inventoryCostingMethod': <dynamic>[_inventoryCostingMethod.code],
      'inventoryCostLayers':
          await loadList(() => InventoryRepository.getInventoryCostLayers()),
      'stockMovements': await loadList(() => StockMovementRepository.listAll()),
      'inventoryCounts': inventoryCounts.map((item) => item.toJson()).toList(),
      'sales': await loadList(() => SaleRepository.listAll()),
      'saleQuotations': await loadList(() => SaleRepository.getQuotations()),
      'deliveryNotes': await loadList(() => SaleRepository.getDeliveryNotes()),
      'purchases': await loadList(() => PurchaseRepository.listAll()),
      'expenses': await loadList(() => ExpenseRepository.listAll()),
      'accountTransactions':
          await loadList(() => AccountTransactionRepository.listAll()),
      'billsOfMaterials':
          await loadList(() => InventoryRepository.getBillOfMaterials()),
      'manufacturingOrders':
          await loadList(() => InventoryRepository.getManufacturingOrders()),
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
  Future<List<Map<String, dynamic>>> exportUnifiedSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    final identity = appIdentity;
    final generatedAt = DateTime.now().toIso8601String();
    final jobId = '${DateTime.now().microsecondsSinceEpoch}-$_deviceId-$kind';
    final collections = await _unifiedSnapshotCollectionPayloads(
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

  Future<List<Map<String, dynamic>>>
      exportCloudLoginBootstrapSnapshotChunks() async {
    return await exportUnifiedSnapshotChunks(
      kind: 'login_bootstrap',
      sectionIds: {UnifiedSnapshotCatalog.loginSettingsAndUsers.id},
    );
  }

  Future<List<Map<String, dynamic>>> exportCloudBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    return await exportUnifiedSnapshotChunks(
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

  Future<String> exportBackupJson() async {
    requirePermission(AppPermission.backupExport);
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(await _backupPayload(includeDeviceAndSyncState: true));
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

  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    final chunks = await exportUnifiedSnapshotChunks(
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

  Future<String> exportSyncSnapshotJson() async {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(await exportUnifiedSnapshotEnvelope(kind: 'full_store'));
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
      'pendingQueue': pendingSyncCount,
      'safeFloorSequence': safeFloorSequence,
      'earliestSequence': _earliestStoredAuthoritativeSequence(),
      'latestSequence': _latestStoredAuthoritativeSequence(),
      'skipped': skipped,
    };
  }

  String _syncHistoryCompactionLogLine(String label, Map<String, int> result) {
    final pendingQueue = result['pendingQueue'] ?? pendingSyncCount;
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
        'remainingQueue=${_syncQueue.length} pendingQueue=$pendingSyncCount',
      );
    }
    if (pendingSyncCount > 0 || pendingSyncChanges.isNotEmpty) {
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
      result['pendingQueue'] = pendingSyncCount;
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

  @override
  void dispose() {
    unawaited(LocalDatabaseService.flushPendingWrites());
    super.dispose();
  }
}
