import 'dart:convert';

import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/account_transaction.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/user_role.dart';

class _CachedEntityList {
  const _CachedEntityList(this.raw, this.items);

  final String raw;
  final Object items;
}

final Map<String, _CachedEntityList> _entityListCache =
    <String, _CachedEntityList>{};

List<T> _decodeEntityList<T>(
  String? raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw == null || raw.trim().isEmpty) return <T>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <T>[];
    return decoded
        .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  } catch (_) {
    return <T>[];
  }
}

List<T> _decodeCachedEntityList<T>(
  String cacheKey,
  String? raw,
  T Function(Map<String, dynamic>) fromJson, {
  bool Function(T item)? include,
  List<T> Function(List<T> items)? sort,
}) {
  final resolvedRaw = raw ?? '';
  final cached = _entityListCache[cacheKey];
  if (cached != null && cached.raw == resolvedRaw) {
    return cached.items as List<T>;
  }
  var items = _decodeEntityList(resolvedRaw, fromJson);
  if (include != null) {
    items = items.where(include).toList(growable: false);
  }
  if (sort != null) {
    items = sort(items);
  }
  final result = List<T>.unmodifiable(items);
  _entityListCache[cacheKey] = _CachedEntityList(resolvedRaw, result);
  return result;
}

List<Product> _sortProducts(List<Product> items) {
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

extension AppStoreTestAccessors on AppStore {
  List<Product> get products => _decodeCachedEntityList(
        'products',
        LocalDatabaseService.getString(BusinessSqliteStore.productsKey),
        (json) => Product.fromJson(json),
        include: (product) => !product.isDeleted,
        sort: _sortProducts,
      );

  List<Product> get stockTrackedProducts => _decodeCachedEntityList(
        'stockTrackedProducts',
        LocalDatabaseService.getString(BusinessSqliteStore.productsKey),
        (json) => Product.fromJson(json),
        include: (product) => !product.isDeleted && product.trackStock,
        sort: _sortProducts,
      );

  List<Customer> get customers => _decodeCachedEntityList(
        'customers',
        LocalDatabaseService.getString(BusinessSqliteStore.customersKey),
        (json) => Customer.fromJson(json),
        include: (customer) => !customer.isDeleted,
      );

  List<CatalogItem> get categories => _decodeCachedEntityList(
        'categories',
        LocalDatabaseService.getString(BusinessSqliteStore.categoriesKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<CatalogItem> get brands => _decodeCachedEntityList(
        'brands',
        LocalDatabaseService.getString(BusinessSqliteStore.brandsKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<CatalogItem> get units => _decodeCachedEntityList(
        'units',
        LocalDatabaseService.getString(BusinessSqliteStore.unitsKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<Sale> get sales => _decodeCachedEntityList(
        'sales',
        LocalDatabaseService.getString(BusinessSqliteStore.salesKey),
        (json) => Sale.fromJson(json),
        include: (sale) => !sale.isDeleted,
      );

  List<Supplier> get suppliers => _decodeCachedEntityList(
        'suppliers',
        LocalDatabaseService.getString(BusinessSqliteStore.suppliersKey),
        (json) => Supplier.fromJson(json),
        include: (supplier) => !supplier.isDeleted,
      );

  List<Expense> get expenses => _decodeCachedEntityList(
        'expenses',
        LocalDatabaseService.getString(BusinessSqliteStore.expensesKey),
        (json) => Expense.fromJson(json),
        include: (expense) => !expense.isDeleted,
      );

  List<Purchase> get purchases => _decodeCachedEntityList(
        'purchases',
        LocalDatabaseService.getString(BusinessSqliteStore.purchasesKey),
        (json) => Purchase.fromJson(json),
        include: (purchase) => !purchase.isDeleted,
      );

  List<StockMovement> get stockMovements => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.stockMovementsKey),
        (json) => StockMovement.fromJson(json),
      );

  List<AccountTransaction> get accountTransactions => _decodeCachedEntityList(
        'accountTransactions',
        LocalDatabaseService.getString(
          BusinessSqliteStore.accountTransactionsKey,
        ),
        (json) => AccountTransaction.fromJson(json),
        include: (transaction) => !transaction.isDeleted,
      );

  List<UserRole> get roles => _decodeCachedEntityList(
        'roles',
        LocalDatabaseService.getString(BusinessSqliteStore.rolesKey),
        (json) => UserRole.fromJson(json),
      );

  List<AppUser> get users => _decodeCachedEntityList(
        'users',
        LocalDatabaseService.getString(BusinessSqliteStore.usersKey),
        (json) => AppUser.fromJson(json),
      );
}
