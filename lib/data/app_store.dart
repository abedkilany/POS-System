import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/local_database_service.dart';

import '../models/catalog_item.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/store_profile.dart';
import '../models/supplier.dart';
import '../models/sync_change.dart';
import '../models/user_role.dart';
import '../models/app_user.dart';

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

class AppStore extends ChangeNotifier {
  static const String walkInCustomerId = 'walk_in';
  static const String walkInCustomerName = 'Walk-in Customer';

  static const _productsKey = 'products_v4';
  static const _customersKey = 'customers_v4';
  static const _salesKey = 'sales_v4';
  static const _suppliersKey = 'suppliers_v4';
  static const _expensesKey = 'expenses_v4';
  static const _storeProfileKey = 'store_profile_v5';
  static const _categoriesKey = 'product_categories_v1';
  static const _brandsKey = 'product_brands_v1';
  static const _unitsKey = 'product_units_v1';
  static const _invoiceCounterKey = 'invoice_counter_v1';
  static const _deviceIdKey = 'sync_device_id_v1';
  static const _syncChangesKey = 'sync_changes_v1';
  static const _schemaVersionKey = 'schema_version_v1';
  static const _pinKey = 'security_pin_v1';
  static const _pinHashPrefix = 'sha256:';
  static const _pinHashV2Prefix = 'sha256salt:';
  static const _currentRoleKey = 'current_role_v1'; // legacy, no longer user-editable
  static const _rolesKey = 'roles_v1';
  static const _usersKey = 'users_v1';
  static const _activeUserKey = 'active_user_v1';

  final List<Product> _products = [];
  final List<Customer> _customers = [];
  final List<Sale> _sales = [];
  final List<Supplier> _suppliers = [];
  final List<CatalogItem> _categories = [];
  final List<CatalogItem> _brands = [];
  final List<CatalogItem> _units = [];
  final List<Expense> _expenses = [];
  final List<SyncChange> _syncChanges = [];
  StoreProfile _storeProfile = StoreProfile.defaults;
  int _invoiceCounter = 0;
  String? _securityPin;
  String _currentRole = 'admin'; // legacy compatibility
  String _deviceId = '';
  final List<UserRole> _roles = [];
  final List<AppUser> _users = [];
  AppUser? _activeUser;

  Customer get walkInCustomer => Customer(
        id: walkInCustomerId,
        name: walkInCustomerName,
        phone: '',
        address: '',
      );

  bool _isReady = false;

  bool get isReady => _isReady;
  List<Product> get products => List.unmodifiable(_products.where((item) => !item.isDeleted));
  List<Customer> get customers => List.unmodifiable(_customers.where((item) => !item.isDeleted));
  List<Sale> get sales => List.unmodifiable(_sales.where((item) => !item.isDeleted).toList().reversed);
  List<Supplier> get suppliers => List.unmodifiable(_suppliers.where((item) => !item.isDeleted));
  List<CatalogItem> get categories => List.unmodifiable(_categories.where((item) => !item.isDeleted));
  List<CatalogItem> get brands => List.unmodifiable(_brands.where((item) => !item.isDeleted));
  List<CatalogItem> get units => List.unmodifiable(_units.where((item) => !item.isDeleted));
  List<Expense> get expenses => List.unmodifiable(_expenses.where((item) => !item.isDeleted).toList().reversed);
  List<SyncChange> get syncChanges => List.unmodifiable(_syncChanges);
  List<SyncChange> get pendingSyncChanges => List.unmodifiable(_syncChanges.where((item) => !item.isSynced));
  String get deviceId => _deviceId;
  int get pendingSyncCount => pendingSyncChanges.length;
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
  bool get isPinEnabled => (_securityPin ?? '').isNotEmpty;
  String get currentRole => currentUserRole?.name ?? _currentRole;
  List<UserRole> get roles => List.unmodifiable(_roles);
  List<AppUser> get users => List.unmodifiable(_users);
  AppUser? get activeUser => _activeUser;
  UserRole? get currentUserRole => _activeUser == null ? null : roleById(_activeUser!.roleId);
  bool get isAdmin => _activeUser?.roleId == 'admin' || currentUserRole?.isAdmin == true;
  bool get canSell => hasPermission(AppPermission.salesCreate);
  bool get canManageProducts => hasPermission(AppPermission.productsCreate) || hasPermission(AppPermission.productsEdit);
  bool get canDeleteOrCancel => hasPermission(AppPermission.salesCancel);
  bool get canManageUsers => hasPermission(AppPermission.usersManage) && hasPermission(AppPermission.rolesManage);

  UserRole? roleById(String id) {
    for (final role in _roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  bool hasPermission(String permission) {
    if (_activeUser == null) return true;
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
  double get totalExpensesAmount => expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
  int get lowStockCount => products.where((item) => item.stock <= 5).length;
  int get totalUnitsInStock => products.fold<int>(0, (sum, item) => sum + item.stock);
  double get inventoryRetailValue => products.fold<double>(0, (sum, item) => sum + (item.price * item.stock));
  double get inventoryCostValue => products.fold<double>(0, (sum, item) => sum + (item.cost * item.stock));

  Future<void> initialize() async {
    await _migrateLegacySharedPreferencesIfNeeded();
    await _ensureDeviceId();

    _products
      ..clear()
      ..addAll(_loadProducts());
    _customers
      ..clear()
      ..addAll(_loadCustomers());
    _sales
      ..clear()
      ..addAll(_loadSales());
    _suppliers
      ..clear()
      ..addAll(_loadSuppliers());
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
    _syncChanges
      ..clear()
      ..addAll(_loadSyncChanges());
    _storeProfile = _loadStoreProfile();
    _invoiceCounter = _loadInvoiceCounter();
    _securityPin = LocalDatabaseService.getString(_pinKey);
    _currentRole = LocalDatabaseService.getString(_currentRoleKey) ?? 'admin';
    _roles
      ..clear()
      ..addAll(_loadRoles());
    _users
      ..clear()
      ..addAll(_loadUsers());
    await _ensureDefaultAdminUser();
    _restoreActiveUser();
    _normalizeCustomers();
    _ensureCatalogDefaults();
    await _runDataMigrationsIfNeeded();

    _isReady = true;
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
      _deviceId = existing.trim();
      return;
    }
    _deviceId = 'DEV-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(999999).toString().padLeft(6, '0')}';
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
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
      final digits = RegExp(r'\d+').allMatches(sale.invoiceNo).map((m) => int.tryParse(m.group(0) ?? '') ?? 0);
      final invoiceNumber = digits.isEmpty ? 0 : digits.reduce((a, b) => a > b ? a : b);
      return invoiceNumber > highest ? invoiceNumber : highest;
    });
    return stored > highestInvoiceNo ? stored : highestInvoiceNo;
  }

  Future<void> _runDataMigrationsIfNeeded() async {
    final current = int.tryParse(LocalDatabaseService.getString(_schemaVersionKey) ?? '') ?? 0;
    if (current >= 9) return;

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
            unitCost: product?.cost ?? 0,
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

    await LocalDatabaseService.setString(_schemaVersionKey, '9');
    await LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString());
    await _saveAll();
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
      );
    }
    for (var index = 0; index < _customers.length; index++) {
      final item = _customers[index];
      _customers[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
      );
    }
    for (var index = 0; index < _sales.length; index++) {
      final item = _sales[index];
      _sales[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? item.date : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
      );
    }
    for (var index = 0; index < _suppliers.length; index++) {
      final item = _suppliers[index];
      _suppliers[index] = item.copyWith(
        createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
        updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
        deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
        syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
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
      );
    }
  }

  CatalogItem _prepareCatalogItemForSync(CatalogItem item, DateTime now) {
    return item.copyWith(
      createdAt: item.createdAt.millisecondsSinceEpoch == 0 ? now : item.createdAt,
      updatedAt: item.updatedAt.millisecondsSinceEpoch == 0 ? now : item.updatedAt,
      deviceId: item.deviceId.isEmpty ? _deviceId : item.deviceId,
      syncStatus: item.syncStatus.isEmpty ? 'synced' : item.syncStatus,
    );
  }

  void _normalizeProductCodes() {
    final used = <String>{};
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      final normalized = product.code.trim().toUpperCase();
      if (normalized.isNotEmpty && !used.contains(normalized)) {
        used.add(normalized);
        continue;
      }
      final generated = _generateUniqueProductCode(exceptProductId: product.id, reservedCodes: used);
      used.add(generated.toUpperCase());
      _products[index] = product.copyWith(code: generated);
    }
  }

  Future<void> setSecurityPin(String pin) async {
    final cleaned = pin.trim();
    if (cleaned.length < 4 || cleaned.length > 8 || int.tryParse(cleaned) == null) {
      throw ArgumentError('PIN must be 4 to 8 digits.');
    }
    _securityPin = _hashPinV2(cleaned);
    await LocalDatabaseService.setString(_pinKey, _securityPin!);
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
    if (_users.isEmpty) {
      _users.add(AppUser(
        id: 'admin',
        fullName: 'Administrator',
        username: 'admin',
        passwordHash: _hashPinV2('admin123'),
        roleId: 'admin',
        isSystem: true,
        createdAt: now,
        updatedAt: now,
      ));
    }
    await _saveRolesAndUsers();
  }

  void _restoreActiveUser() {
    final activeId = LocalDatabaseService.getString(_activeUserKey);
    if (activeId == null || activeId.isEmpty) return;
    for (final user in _users) {
      if (user.id == activeId && user.isActive) {
        _activeUser = user;
        return;
      }
    }
  }

  Future<bool> login(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    for (var index = 0; index < _users.length; index++) {
      final user = _users[index];
      if (user.username.trim().toLowerCase() != normalized || !user.isActive) continue;
      if (!_verifyPassword(password, user.passwordHash)) return false;
      final updated = user.copyWith(lastLoginAt: DateTime.now());
      _users[index] = updated;
      _activeUser = updated;
      await LocalDatabaseService.setString(_activeUserKey, updated.id);
      await _saveRolesAndUsers();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    _activeUser = null;
    await LocalDatabaseService.setString(_activeUserKey, '');
    notifyListeners();
  }

  bool _verifyPassword(String password, String storedHash) {
    if (storedHash.startsWith(_pinHashV2Prefix)) {
      final parts = storedHash.split(':');
      if (parts.length != 3) return false;
      return storedHash == _hashPinWithSalt(password.trim(), parts[1]);
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
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> deleteRole(String id) async {
    requirePermission(AppPermission.rolesManage);
    if (id == 'admin') throw StateError('The Admin role cannot be deleted.');
    if (_users.any((user) => user.roleId == id)) throw StateError('Move users to another role before deleting this role.');
    _roles.removeWhere((role) => role.id == id && !role.isSystem);
    await _saveRolesAndUsers();
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
      passwordHash: password != null && password.trim().isNotEmpty ? _hashPinV2(password.trim()) : user.passwordHash,
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
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> deleteUser(String id) async {
    requirePermission(AppPermission.usersManage);
    final user = _users.firstWhere((item) => item.id == id);
    final adminCount = _users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) throw StateError('Create another active admin before deleting this user.');
    if (user.isSystem) throw StateError('The built-in admin user cannot be deleted.');
    _users.removeWhere((item) => item.id == id);
    await _saveRolesAndUsers();
    notifyListeners();
  }

  Future<void> clearSecurityPin() async {
    _securityPin = null;
    await LocalDatabaseService.setString(_pinKey, '');
    notifyListeners();
  }

  bool verifySecurityPin(String pin) {
    final stored = _securityPin ?? '';
    final cleaned = pin.trim();
    if (stored.startsWith(_pinHashV2Prefix)) {
      final parts = stored.split(':');
      if (parts.length != 3) return false;
      return stored == _hashPinWithSalt(cleaned, parts[1]);
    }

    if (stored.startsWith(_pinHashPrefix)) {
      final isMatch = stored == _hashLegacyPin(cleaned);
      if (isMatch) {
        _securityPin = _hashPinV2(cleaned);
        LocalDatabaseService.setString(_pinKey, _securityPin!);
      }
      return isMatch;
    }

    final isLegacyMatch = stored == cleaned;
    if (isLegacyMatch) {
      _securityPin = _hashPinV2(cleaned);
      LocalDatabaseService.setString(_pinKey, _securityPin!);
    }
    return isLegacyMatch;
  }

  String _hashPinV2(String pin) {
    final salt = _generateSalt();
    return _hashPinWithSalt(pin, salt);
  }

  String _hashPinWithSalt(String pin, String salt) {
    List<int> digest = utf8.encode('store_manager_pro|local_pin_v2|$salt|$pin');
    for (var i = 0; i < 12000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '$_pinHashV2Prefix$salt:${base64UrlEncode(digest)}';
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashLegacyPin(String pin) {
    final bytes = utf8.encode('store_manager_pro|local_pin_v1|$pin');
    return '$_pinHashPrefix${sha256.convert(bytes)}';
  }

  StoreProfile _loadStoreProfile() {
    final raw = LocalDatabaseService.getString(_storeProfileKey);
    if (raw == null) return StoreProfile.defaults;
    return StoreProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  void _normalizeCustomers() {
    final normalized = <Customer>[];
    var hasWalkIn = false;
    final seenIds = <String>{};
    final seenNames = <String>{};

    for (final customer in _customers) {
      final normalizedName = customer.name.trim().toLowerCase();
      final isWalkIn = customer.id == walkInCustomerId || normalizedName == walkInCustomerName.toLowerCase();

      if (isWalkIn) {
        if (!hasWalkIn) {
          normalized.add(walkInCustomer);
          hasWalkIn = true;
          seenIds.add(walkInCustomerId);
          seenNames.add(walkInCustomerName.toLowerCase());
        }
        continue;
      }

      if (seenIds.contains(customer.id) || seenNames.contains(normalizedName)) {
        continue;
      }

      normalized.add(customer.copyWith(name: customer.name.trim()));
      seenIds.add(customer.id);
      seenNames.add(normalizedName);
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

  Future<void> _saveAll() async {
    _normalizeCustomers();
    await LocalDatabaseService.setString(_productsKey, jsonEncode(_products.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_customersKey, jsonEncode(_customers.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_salesKey, jsonEncode(_sales.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_suppliersKey, jsonEncode(_suppliers.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_categoriesKey, jsonEncode(_categories.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_brandsKey, jsonEncode(_brands.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_unitsKey, jsonEncode(_units.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_expensesKey, jsonEncode(_expenses.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_syncChangesKey, jsonEncode(_syncChanges.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(_deviceIdKey, _deviceId);
    await LocalDatabaseService.setString(_storeProfileKey, jsonEncode(_storeProfile.toJson()));
    await LocalDatabaseService.setString(_invoiceCounterKey, _invoiceCounter.toString());
    await LocalDatabaseService.setString(_schemaVersionKey, '9');
  }


  Product? _findProductById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Product? findProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    for (final product in _products) {
      if (product.code.trim().toLowerCase() == normalized) return product;
    }
    return null;
  }


  void _resetBusinessDataInMemory({bool keepStoreProfile = true, bool keepSecurityPin = true}) {
    _products.clear();
    _customers
      ..clear()
      ..add(walkInCustomer);
    _sales.clear();
    _suppliers.clear();
    _expenses.clear();
    _invoiceCounter = 0;
    if (!keepStoreProfile) {
      _storeProfile = StoreProfile.defaults;
    }
    if (!keepSecurityPin) {
      _securityPin = null;
    }
  }

  Future<void> resetBusinessData({bool keepStoreProfile = true, bool keepSecurityPin = true}) async {
    requirePermission(AppPermission.backupRestore);

    // A business-data reset is a central sync event. Clear the old change log so
    // clients that come back online receive the reset marker without replaying
    // stale pre-reset operations.
    _syncChanges.clear();
    _resetBusinessDataInMemory(keepStoreProfile: keepStoreProfile, keepSecurityPin: keepSecurityPin);
    if (!keepSecurityPin) {
      await LocalDatabaseService.setString(_pinKey, '');
    }
    _recordSyncChange(
      entityType: 'system',
      entityId: 'store',
      operation: 'reset_store_data',
      payload: {
        'keepStoreProfile': keepStoreProfile,
        'keepSecurityPin': keepSecurityPin,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateStoreProfile(StoreProfile profile) async {
    requirePermission(AppPermission.settingsManage);
    _storeProfile = profile;
    await _saveAll();
    notifyListeners();
  }

  void _validateProduct(Product product) {
    if (product.name.trim().isEmpty || product.code.trim().isEmpty || product.category.trim().isEmpty) {
      throw ArgumentError('Product name, code, and category are required.');
    }
    if (!product.price.isFinite || !product.cost.isFinite || product.price < 0 || product.cost < 0 || product.stock < 0 || product.lowStockThreshold < 0) {
      throw ArgumentError('Product price, cost, stock, and low stock threshold must be zero or positive.');
    }
    final normalizedCode = product.code.trim().toLowerCase();
    final normalizedBarcode = product.barcode.trim().toLowerCase();
    final duplicate = _products.any((item) {
      if (item.id == product.id) return false;
      final sameCode = item.code.trim().toLowerCase() == normalizedCode;
      final sameBarcode = normalizedBarcode.isNotEmpty && item.barcode.trim().toLowerCase() == normalizedBarcode;
      return sameCode || sameBarcode;
    });
    if (duplicate) {
      throw ArgumentError('Product code or barcode already exists.');
    }
  }


  String _generateUniqueProductCode({String? exceptProductId, Set<String>? reservedCodes}) {
    final used = {
      ..._products.where((item) => item.id != exceptProductId).map((item) => item.code.trim().toUpperCase()),
      ...?reservedCodes,
    };
    var counter = _products.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }


  void _recordSyncChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    final now = DateTime.now();
    _syncChanges.add(SyncChange(
      id: '${now.microsecondsSinceEpoch}-${_syncChanges.length}',
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      deviceId: _deviceId,
      createdAt: now,
      payload: payload,
    ));
  }

  Product _markProductForSync(Product product, DateTime now, {bool isCreate = false}) {
    return product.copyWith(
      createdAt: isCreate ? now : product.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      clearDeletedAt: true,
    );
  }

  CatalogItem _markCatalogItemForSync(CatalogItem item, DateTime now, {bool isCreate = false}) {
    return item.copyWith(
      createdAt: isCreate ? now : item.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      clearDeletedAt: true,
    );
  }

  Future<void> addOrUpdateProduct(Product product) async {
    final exists = _products.any((item) => item.id == product.id);
    requirePermission(exists ? AppPermission.productsEdit : AppPermission.productsCreate);
    final now = DateTime.now();
    final normalizedProduct = product.code.trim().isEmpty ? product.copyWith(code: _generateUniqueProductCode(exceptProductId: product.id)) : product;
    _validateProduct(normalizedProduct);

    final index = _products.indexWhere((item) => item.id == normalizedProduct.id);
    final isCreate = index == -1;
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
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    requirePermission(AppPermission.productsDelete);
    final index = _products.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    _products[index] = _products[index].copyWith(deletedAt: now, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
    _recordSyncChange(entityType: 'product', entityId: id, operation: 'delete', payload: _products[index].toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> addOrUpdateCustomer(Customer customer) async {
    requirePermission(AppPermission.customersManage);
    if (customer.name.trim().isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final now = DateTime.now();
    final normalizedName = customer.name.trim();
    final incoming = (customer.id == walkInCustomerId || normalizedName.toLowerCase() == walkInCustomerName.toLowerCase())
        ? walkInCustomer.copyWith(updatedAt: now, deviceId: _deviceId, syncStatus: 'pending')
        : customer.copyWith(name: normalizedName, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', clearDeletedAt: true);

    final index = _customers.indexWhere((item) => item.id == incoming.id);
    final isCreate = index == -1;
    final syncedCustomer = isCreate ? incoming.copyWith(createdAt: now) : incoming;
    if (isCreate) {
      _customers.add(syncedCustomer);
    } else {
      _customers[index] = syncedCustomer;
    }
    _recordSyncChange(entityType: 'customer', entityId: syncedCustomer.id, operation: isCreate ? 'create' : 'update', payload: syncedCustomer.toJson());
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    requirePermission(AppPermission.customersManage);
    if (id == walkInCustomerId) return;
    final index = _customers.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    _customers[index] = _customers[index].copyWith(deletedAt: now, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
    _recordSyncChange(entityType: 'customer', entityId: id, operation: 'delete', payload: _customers[index].toJson());
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

  Future<void> addOrUpdateSupplier(Supplier supplier) async {
    requirePermission(AppPermission.suppliersManage);
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final now = DateTime.now();
    final index = _suppliers.indexWhere((item) => item.id == supplier.id);
    final isCreate = index == -1;
    final syncedSupplier = supplier.copyWith(createdAt: isCreate ? now : supplier.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', clearDeletedAt: true);
    if (isCreate) {
      _suppliers.add(syncedSupplier);
    } else {
      _suppliers[index] = syncedSupplier;
    }
    _recordSyncChange(entityType: 'supplier', entityId: syncedSupplier.id, operation: isCreate ? 'create' : 'update', payload: syncedSupplier.toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteSupplier(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _suppliers.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    _suppliers[index] = _suppliers[index].copyWith(deletedAt: now, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
    _recordSyncChange(entityType: 'supplier', entityId: id, operation: 'delete', payload: _suppliers[index].toJson());
    await _saveAll();
    notifyListeners();
  }


  Future<void> addOrUpdateCategory(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_categories, item);
    _recordSyncChange(entityType: 'category', entityId: syncedItem.id, operation: _categories.where((existing) => existing.id == syncedItem.id).length == 1 && syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> addOrUpdateBrand(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_brands, item);
    _recordSyncChange(entityType: 'brand', entityId: syncedItem.id, operation: syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> addOrUpdateUnit(CatalogItem item) async {
    requirePermission(AppPermission.catalogManage);
    final syncedItem = _addOrUpdateCatalogItem(_units, item);
    _recordSyncChange(entityType: 'unit', entityId: syncedItem.id, operation: syncedItem.createdAt == syncedItem.updatedAt ? 'create' : 'update', payload: syncedItem.toJson());
    await _saveAll();
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
    if (expense.title.trim().isEmpty || expense.category.trim().isEmpty || !expense.amount.isFinite || expense.amount < 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final now = DateTime.now();
    final index = _expenses.indexWhere((item) => item.id == expense.id);
    final isCreate = index == -1;
    final syncedExpense = expense.copyWith(createdAt: isCreate ? now : expense.createdAt, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending', clearDeletedAt: true);
    if (isCreate) {
      _expenses.add(syncedExpense);
    } else {
      _expenses[index] = syncedExpense;
    }
    _recordSyncChange(entityType: 'expense', entityId: syncedExpense.id, operation: isCreate ? 'create' : 'update', payload: syncedExpense.toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    requirePermission(AppPermission.expensesManage);
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    _expenses[index] = _expenses[index].copyWith(deletedAt: now, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
    _recordSyncChange(entityType: 'expense', entityId: id, operation: 'delete', payload: _expenses[index].toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<Sale> createSale({
    required String customerName,
    required List<SaleItem> items,
    double discount = 0,
    String paymentMethod = 'Cash',
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
      if (product.stock < item.quantity) {
        throw StateError('Not enough stock for ${product.name}.');
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
        unitCost: item.unitCost > 0 ? item.unitCost : product.cost,
      );
    }).toList();

    final now = DateTime.now();
    final sale = Sale(
      id: now.microsecondsSinceEpoch.toString(),
      invoiceNo: 'INV-${_invoiceCounter.toString().padLeft(6, '0')}',
      customerName: customerName.trim().isEmpty ? walkInCustomerName : customerName.trim(),
      date: now,
      status: 'Paid',
      paymentMethod: paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim(),
      items: saleItems,
      discount: cleanedDiscount,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
    );

    _sales.add(sale);
    _recordSyncChange(entityType: 'sale', entityId: sale.id, operation: 'create', payload: sale.toJson());

    for (final item in saleItems) {
      final index = _products.indexWhere((product) => product.id == item.productId);
      final product = _products[index];
      final updatedProduct = product.copyWith(stock: product.stock - item.quantity, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
      _products[index] = updatedProduct;
      _recordSyncChange(entityType: 'stock_movement', entityId: '${sale.id}-${item.productId}', operation: 'sale_decrement', payload: {
        'saleId': sale.id,
        'productId': item.productId,
        'quantity': -item.quantity,
        'createdAt': now.toIso8601String(),
        'deviceId': _deviceId,
      });
    }

    await _saveAll();
    notifyListeners();
    return sale;
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
        final now = DateTime.now();
        final updatedProduct = product.copyWith(stock: product.stock + item.quantity, updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
        _products[productIndex] = updatedProduct;
        _recordSyncChange(entityType: 'stock_movement', entityId: '$id-${item.productId}-restore', operation: 'sale_restore', payload: {
          'saleId': id,
          'productId': item.productId,
          'quantity': item.quantity,
          'createdAt': now.toIso8601String(),
          'deviceId': _deviceId,
        });
      }
    }

    final now = DateTime.now();
    _sales[index] = sale.copyWith(status: status, note: 'Stock restored on ${now.toIso8601String()}', updatedAt: now, deviceId: _deviceId, syncStatus: 'pending');
    _recordSyncChange(entityType: 'sale', entityId: id, operation: 'cancel', payload: _sales[index].toJson());
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteSale(String id, {bool restoreStock = true}) async {
    // Kept for compatibility. Business flow now cancels invoices instead of deleting them.
    await cancelSale(id, status: 'Cancelled', restoreStock: restoreStock);
  }

  double estimateProfit() {
    final grossProfit = sales.fold<double>(0, (sum, sale) => sum + sale.grossProfit);
    return grossProfit - totalExpensesAmount;
  }

  Map<String, dynamic> _backupPayload({List<SyncChange>? changes}) => {
        'version': 11,
        'generatedAt': DateTime.now().toIso8601String(),
        'schemaVersion': 11,
        'invoiceCounter': _invoiceCounter,
        'storeProfile': _storeProfile.toJson(),
        'products': _products.map((item) => item.toJson()).toList(),
        'customers': _customers.map((item) => item.toJson()).toList(),
        'sales': _sales.map((item) => item.toJson()).toList(),
        'suppliers': _suppliers.map((item) => item.toJson()).toList(),
        'categories': _categories.map((item) => item.toJson()).toList(),
        'brands': _brands.map((item) => item.toJson()).toList(),
        'units': _units.map((item) => item.toJson()).toList(),
        'expenses': _expenses.map((item) => item.toJson()).toList(),
        'deviceId': _deviceId,
        'syncChanges': (changes ?? _syncChanges).map((item) => item.toJson()).toList(),
        'roles': _roles.map((item) => item.toJson()).toList(),
        'users': _users.map((item) => item.toJson()).toList(),
      };

  String exportBackupJson() {
    requirePermission(AppPermission.backupExport);
    return const JsonEncoder.withIndent('  ').convert(_backupPayload());
  }

  String exportSyncSnapshotJson() => const JsonEncoder.withIndent('  ').convert(_backupPayload());

  String exportSyncChangesJson({DateTime? since}) {
    final changes = since == null ? _syncChanges : _syncChanges.where((item) => item.createdAt.isAfter(since)).toList();
    return jsonEncode({
      'ok': true,
      'deviceId': _deviceId,
      'generatedAt': DateTime.now().toIso8601String(),
      'changes': changes.map((item) => item.toJson()).toList(),
    });
  }

  String exportEncryptedBackupJson(String password) {
    requirePermission(AppPermission.backupExport);
    final cleaned = password.trim();
    if (cleaned.length < 6) {
      throw ArgumentError('Backup password must be at least 6 characters.');
    }
    final plain = exportBackupJson();
    final salt = _generateSalt();
    final key = _deriveBackupKey(cleaned, salt);
    final bytes = utf8.encode(plain);
    final encrypted = List<int>.generate(bytes.length, (index) => bytes[index] ^ key[index % key.length]);
    final payload = {
      'format': 'store_manager_pro_encrypted_backup',
      'version': 1,
      'salt': salt,
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
    final key = _deriveBackupKey(password.trim(), salt);
    final encrypted = base64Url.decode(data);
    final plain = List<int>.generate(encrypted.length, (index) => encrypted[index] ^ key[index % key.length]);
    return utf8.decode(plain);
  }

  List<int> _deriveBackupKey(String password, String salt) {
    List<int> digest = utf8.encode('store_manager_pro|backup_v1|$salt|$password');
    for (var i = 0; i < 25000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  Future<void> importBackupJson(String rawJson) async {
    requirePermission(AppPermission.backupRestore);
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
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
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
    final syncChanges = (decoded['syncChanges'] as List<dynamic>? ?? [])
        .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
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
    _suppliers
      ..clear()
      ..addAll(suppliers);
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
    _syncChanges
      ..clear()
      ..addAll(syncChanges);
    _storeProfile = profile;
    if (roles.isNotEmpty) {
      _roles
        ..clear()
        ..addAll(roles);
    }
    if (users.isNotEmpty) {
      _users
        ..clear()
        ..addAll(users);
    }
    await _ensureDefaultAdminUser();
    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    _invoiceCounter = importedCounter > 0 ? importedCounter : _loadInvoiceCounter();
    _normalizeCustomers();

    await _saveAll();
    notifyListeners();
  }



  DateTime _readUpdatedAt(dynamic item) {
    try {
      final updatedAt = item.updatedAt as DateTime;
      return updatedAt;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
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
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
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
    final syncChanges = (decoded['syncChanges'] as List<dynamic>? ?? [])
        .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
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
    _mergeByUpdatedAt<Supplier>(_suppliers, suppliers, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_categories, categories, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_brands, brands, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_units, units, (item) => item.id);
    _mergeByUpdatedAt<Expense>(_expenses, expenses, (item) => item.id);
    _mergeSyncChanges(syncChanges);

    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    if (importedCounter > _invoiceCounter) _invoiceCounter = importedCounter;

    if (markSynced) {
      final now = DateTime.now();
      for (var i = 0; i < _syncChanges.length; i++) {
        _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
      }
    }

    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

  Future<void> markAllSyncChangesSynced() async {
    final now = DateTime.now();
    for (var i = 0; i < _syncChanges.length; i++) {
      _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> importSyncSnapshotJson(String rawJson) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    await _replaceFromBackupMap(decoded);
  }

  Future<void> _replaceFromBackupMap(Map<String, dynamic> decoded) async {
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map((item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map((item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)))
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
    final syncChanges = (decoded['syncChanges'] as List<dynamic>? ?? [])
        .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
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
    _suppliers..clear()..addAll(suppliers);
    _categories..clear()..addAll(categories);
    _brands..clear()..addAll(brands);
    _units..clear()..addAll(units);
    _expenses..clear()..addAll(expenses);
    _syncChanges..clear()..addAll(syncChanges);
    _storeProfile = profile;
    if (roles.isNotEmpty) _roles..clear()..addAll(roles);
    if (users.isNotEmpty) _users..clear()..addAll(users);
    await _ensureDefaultAdminUser();
    _invoiceCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? _invoiceCounter;
    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveAll();
    notifyListeners();
  }

  Future<void> applyRemoteSyncChanges(List<SyncChange> incoming, {bool markAppliedAsSynced = false}) async {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    final sorted = [...incoming]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var changed = false;
    for (final change in sorted) {
      if (existingIds.contains(change.id)) continue;
      _applySyncChangePayload(change);
      _syncChanges.add(markAppliedAsSynced ? change.copyWith(isSynced: true, syncedAt: DateTime.now()) : change);
      existingIds.add(change.id);
      changed = true;
    }
    if (changed) {
      _ensureCatalogDefaults();
      _normalizeCustomers();
      await _saveAll();
      notifyListeners();
    }
  }

  void _upsertByUpdatedAt<T>(List<T> list, T incoming, String Function(T item) idOf) {
    final index = list.indexWhere((item) => idOf(item) == idOf(incoming));
    if (index == -1) {
      list.add(incoming);
    } else if (_readUpdatedAt(incoming).isAfter(_readUpdatedAt(list[index])) || _readUpdatedAt(incoming).isAtSameMomentAs(_readUpdatedAt(list[index]))) {
      list[index] = incoming;
    }
  }

  void _applySyncChangePayload(SyncChange change) {
    final p = change.payload;
    switch (change.entityType) {
      case 'system':
        if (change.operation == 'reset_store_data') {
          _syncChanges.clear();
          _resetBusinessDataInMemory(
            keepStoreProfile: p['keepStoreProfile'] as bool? ?? true,
            keepSecurityPin: p['keepSecurityPin'] as bool? ?? true,
          );
        }
        break;
      case 'product':
        _upsertByUpdatedAt<Product>(_products, Product.fromJson(p), (item) => item.id);
        break;
      case 'customer':
        _upsertByUpdatedAt<Customer>(_customers, Customer.fromJson(p), (item) => item.id);
        break;
      case 'supplier':
        _upsertByUpdatedAt<Supplier>(_suppliers, Supplier.fromJson(p), (item) => item.id);
        break;
      case 'expense':
        _upsertByUpdatedAt<Expense>(_expenses, Expense.fromJson(p), (item) => item.id);
        break;
      case 'category':
        _upsertByUpdatedAt<CatalogItem>(_categories, CatalogItem.fromJson(p), (item) => item.id);
        break;
      case 'brand':
        _upsertByUpdatedAt<CatalogItem>(_brands, CatalogItem.fromJson(p), (item) => item.id);
        break;
      case 'unit':
        _upsertByUpdatedAt<CatalogItem>(_units, CatalogItem.fromJson(p), (item) => item.id);
        break;
      case 'sale':
        _upsertByUpdatedAt<Sale>(_sales, Sale.fromJson(p), (item) => item.id);
        break;
      case 'stock_movement':
        final productId = p['productId'] as String? ?? '';
        final quantity = (p['quantity'] as num?)?.toInt() ?? 0;
        final index = _products.indexWhere((item) => item.id == productId);
        if (index != -1 && quantity != 0) {
          final product = _products[index];
          final at = DateTime.tryParse(p['createdAt'] as String? ?? '') ?? change.createdAt;
          _products[index] = product.copyWith(
            stock: product.stock + quantity,
            updatedAt: at.isAfter(product.updatedAt) ? at : product.updatedAt,
            syncStatus: 'synced',
          );
        }
        break;
    }
  }

  Future<void> markSyncChangesSyncedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    for (var i = 0; i < _syncChanges.length; i++) {
      if (idSet.contains(_syncChanges[i].id)) {
        _syncChanges[i] = _syncChanges[i].copyWith(isSynced: true, syncedAt: now);
      }
    }
    await _saveAll();
    notifyListeners();
  }

  BackupSummary get currentBackupSummary => BackupSummary(
        version: 10,
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

      final map = Map<String, dynamic>.from(decoded as Map);
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
