import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../../models/account_transaction.dart';
import '../../models/catalog_item.dart';
import '../../models/app_user.dart';
import '../../models/customer.dart';
import '../../models/delivery_note.dart';
import '../../models/expense.dart';
import '../../models/inventory_count.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/product_pricing.dart';
import '../../models/purchase_item.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/sale_quotation.dart';
import '../../models/sale_summary.dart';
import '../../models/stock_movement.dart';
import '../../models/supplier.dart';
import '../../models/supplier_purchase_price.dart';
import '../../models/supplier_product_price.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import '../../models/user_role.dart';
import '../../models/warehouse.dart';
import '../services/accounting_service.dart';
import '../services/local_database_service.dart';
import '../services/password_hashing.dart';
import 'business_session_context.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';

VentioDriftDatabase? _businessDb() => SqliteMigrationManager.database;

const String _walkInCustomerId = 'walk_in';
const String _walkInCustomerName = 'Walk-In Customer';

Future<List<T>> _readBusinessEntityList<T>(
  String key,
  T Function(Map<String, dynamic>) fromJson,
) async {
  final raw = await LocalDatabaseService.getBusinessEntityListJson(key);
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

Future<int> _countBusinessEntityList(String key) async {
  final raw = await LocalDatabaseService.getBusinessEntityListJson(key);
  if (raw == null || raw.trim().isEmpty) return 0;
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.length : 0;
  } catch (_) {
    return 0;
  }
}

Future<void> _refreshMaterializedSummaries({
  bool force = false,
}) async {
  final db = _businessDb();
  if (db == null) return;
  await BusinessSqliteStore.refreshSummaryTables(
    db,
    reference: DateTime.now(),
    force: force,
  );
}

Future<void> _saveBusinessRow(
  String key,
  Map<String, dynamic> payload, {
  int? sortIndex,
}) async {
  await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
    key,
    payload,
    sortIndex: sortIndex,
  );
}

Future<void> _recordBusinessSyncChange({
  required BusinessSessionContext context,
  required String entityType,
  required String entityId,
  required String operation,
  required Map<String, dynamic> payload,
}) async {
  final now = DateTime.now();
  final changeId = '${context.deviceId}-${now.microsecondsSinceEpoch}';
  final change = SyncChange(
    id: changeId,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    deviceId: context.deviceId,
    createdAt: now,
    payload: payload,
    storeId: context.appIdentity.storeId,
    branchId: context.appIdentity.branchId,
    storeEpoch: context.appIdentity.storeEpoch,
  );
  await LocalDatabaseService.upsertSyncChange(change);

  final identity = context.appIdentity;
  final activeTransport = identity.activeSyncTransportNormalized;
  final target = identity.isHost && identity.isCloudEnabled
      ? 'cloud'
      : identity.isClient && activeTransport == 'cloud'
          ? 'cloud_host'
          : identity.isClient && activeTransport == 'lan'
              ? 'host'
              : 'local';
  if (target == 'local') return;
  await LocalDatabaseService.upsertSyncQueueItem(
    SyncQueueItem(
      id: '$changeId-$target',
      changeId: changeId,
      target: target,
      status: 'pending',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<int> _nextCounter(String key) async {
  final current = int.tryParse(LocalDatabaseService.getString(key) ?? '') ?? 0;
  final next = current + 1;
  await LocalDatabaseService.setString(key, next.toString());
  return next;
}

String _cleanIdentifier(String value, {String fallback = ''}) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (normalized.isEmpty) return fallback;
  return normalized;
}

String _invoicePrefix(BusinessSessionContext context) {
  final clean = _cleanIdentifier(context.deviceId, fallback: 'LOCAL');
  final padded = clean.padRight(4, '0').substring(0, 4);
  return context.appIdentity.isHost ? 'H$padded' : 'C$padded';
}

String _purchasePrefix(BusinessSessionContext context) {
  final clean = _cleanIdentifier(context.deviceId, fallback: 'LOCAL');
  return clean.padRight(4, '0').substring(0, 4);
}

Future<void> _refreshEntityAndSync(
  BusinessSessionContext context,
  String key, {
  bool refreshSummaries = true,
}) async {
  if (refreshSummaries) {
    await _refreshMaterializedSummaries();
  }
  await context.refreshAfterDatabaseChange(key);
  await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
}

Future<void> _upsertEntityJson(
  String key,
  Map<String, dynamic> payload, {
  int? sortIndex,
}) async {
  await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
    key,
    payload,
    sortIndex: sortIndex,
  );
}

Future<void> _softDeleteEntityJson(
  String key,
  Map<String, dynamic> payload,
) async {
  await _upsertEntityJson(key, payload);
}

const String _invoiceCounterKey = 'invoice_counter_v1';
const String _purchaseCounterKey = 'purchase_counter_v1';

class ProductRepository {
  ProductRepository._();

  static Future<BusinessQueryPage<Product>?> queryPage({
    String query = '',
    String category = '',
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
    bool stockTrackedOnly = false,
  }) async {
    final db = _businessDb();
    if (db == null) {
      final all = await listAll();
      final normalizedQuery = query.trim().toLowerCase();
      final normalizedCategory = category.trim().toLowerCase();
      final filtered = all.where((product) {
        if (product.isDeleted) return false;
        if (activeOnly && product.isDeleted) return false;
        if (stockTrackedOnly && !product.trackStock) return false;
        if (normalizedCategory.isNotEmpty &&
            product.category.trim().toLowerCase() != normalizedCategory) {
          return false;
        }
        if (normalizedQuery.isEmpty) return true;
        final haystack = <String>[
          product.name,
          product.nameEn,
          product.nameAr,
          product.code,
          product.barcode,
          product.category,
          product.brand,
          product.supplier,
          product.description,
          product.unit,
        ].join(' ').toLowerCase();
        return haystack.contains(normalizedQuery);
      }).toList(growable: false);
      final safeOffset = offset < 0 ? 0 : offset;
      final safeLimit = limit <= 0 ? filtered.length : limit;
      final end = (safeOffset + safeLimit < filtered.length)
          ? safeOffset + safeLimit
          : filtered.length;
      final items = safeOffset >= filtered.length
          ? <Product>[]
          : filtered.sublist(safeOffset, end);
      return BusinessQueryPage<Product>(
        items: items,
        totalCount: filtered.length,
        limit: safeLimit,
        offset: safeOffset,
      );
    }
    return BusinessSqliteStore.queryProducts(
      db,
      query: query,
      category: category,
      limit: limit,
      offset: offset,
      activeOnly: activeOnly,
      stockTrackedOnly: stockTrackedOnly,
    );
  }

  @Deprecated('Large-app mode: use queryPage() with LIMIT/OFFSET instead.')
  static Future<List<Product>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProducts(db);
  }

  static Future<List<Product>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.productsKey,
        (json) => Product.fromJson(json),
      );

  static Future<int> countAll() async {
    final page = await queryPage(limit: 1);
    if (page != null) return page.totalCount;
    final products = await listAll();
    return products.where((product) => !product.isDeleted).length;
  }

  static Future<List<String>?> getCategories() async {
    final db = _businessDb();
    if (db == null) {
      final items = await _readBusinessEntityList(
        BusinessSqliteStore.categoriesKey,
        (json) => CatalogItem.fromJson(json),
      );
      return items
          .where((item) => !item.isDeleted)
          .map((item) => item.nameEn)
          .where((name) => name.trim().isNotEmpty)
          .toList(growable: false);
    }
    return BusinessSqliteStore.queryProductCategories(db);
  }

  static Future<Product?> getById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }
    return BusinessSqliteStore.readProductById(db, id);
  }

  static Future<Product?> getCoreById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }
    return BusinessSqliteStore.readProductCoreById(db, id);
  }

  static Future<Product?> findByCodeOrBarcode(String code) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProductByCodeOrBarcode(db, code);
  }

  static Future<Product> addOrUpdateProduct(
    BusinessSessionContext context,
    Product product,
  ) async {
    final existing = await getById(product.id);
    final isCreate = existing == null;
    context.requirePermission(
      isCreate ? AppPermission.productsCreate : AppPermission.productsEdit,
    );

    final code = product.code.trim().isEmpty
        ? 'P-${DateTime.now().microsecondsSinceEpoch}'
        : product.code.trim();
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
    final duplicateCode = await countByCode(code, excludeProductId: product.id);
    if ((duplicateCode ?? 0) > 0) {
      throw ArgumentError('Product code must be unique.');
    }
    if (product.barcode.trim().isNotEmpty) {
      final duplicateBarcode = await countByBarcode(
        product.barcode,
        excludeProductId: product.id,
      );
      if ((duplicateBarcode ?? 0) > 0) {
        throw ArgumentError('Product barcode must be unique.');
      }
    }

    final now = DateTime.now();
    final updated = product.copyWith(
      code: code,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: isCreate ? 1 : product.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(
      BusinessSqliteStore.productsKey,
      updated.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product',
      entityId: updated.id,
      operation: isCreate ? 'create' : 'update',
      payload: updated.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return updated;
  }

  static Future<void> deleteProduct(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.productsDelete);
    final existing = await getById(id);
    if (existing == null) return;
    final db = _businessDb();
    if (db != null) {
      final refs = await db.customSelect('''
        SELECT
          (SELECT COUNT(*) FROM sale_items WHERE product_id = ?) AS saleCount,
          (SELECT COUNT(*) FROM purchase_items WHERE product_id = ?) AS purchaseCount,
          (SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND deleted_at = '') AS movementCount
      ''', variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(id),
        Variable<String>(id),
      ]).getSingle();
      final saleCount = (refs.data['saleCount'] as num?)?.toInt() ?? 0;
      final purchaseCount = (refs.data['purchaseCount'] as num?)?.toInt() ?? 0;
      final movementCount = (refs.data['movementCount'] as num?)?.toInt() ?? 0;
      if (saleCount > 0 || purchaseCount > 0 || movementCount > 0) {
        throw StateError(
          'Cannot delete a product that is used by sales, purchases, or stock movements. Deactivate it instead.',
        );
      }
    }
    final now = DateTime.now();
    final deleted = existing.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: existing.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(BusinessSqliteStore.productsKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product',
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<List<CostingMethodHistory>> listCostingMethodHistory() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.costingMethodHistoryKey,
        (json) => CostingMethodHistory.fromJson(json),
      );

  static Future<int?> countByCode(
    String code, {
    String? excludeProductId,
  }) async {
    final db = _businessDb();
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    if (db == null) {
      final products = await listAll();
      return products
          .where((product) =>
              !product.isDeleted &&
              product.code.trim().toLowerCase() == normalized &&
              (excludeProductId == null ||
                  excludeProductId.trim().isEmpty ||
                  product.id != excludeProductId.trim()))
          .length;
    }
    final variables = <Variable<Object>>[
      Variable<String>(normalized),
    ];
    final whereSql = StringBuffer("deleted_at = '' AND lower(code) = ?");
    if (excludeProductId != null && excludeProductId.trim().isNotEmpty) {
      whereSql.write(' AND id <> ?');
      variables.add(Variable<String>(excludeProductId.trim()));
    }
    final row = await db.customSelect(
      'SELECT COUNT(*) AS value FROM products WHERE ${whereSql.toString()}',
      variables: variables,
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  static Future<int?> countByBarcode(
    String barcode, {
    String? excludeProductId,
  }) async {
    final db = _businessDb();
    final normalized = barcode.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    if (db == null) {
      final products = await listAll();
      return products
          .where((product) =>
              !product.isDeleted &&
              product.barcode.trim().toLowerCase() == normalized &&
              (excludeProductId == null ||
                  excludeProductId.trim().isEmpty ||
                  product.id != excludeProductId.trim()))
          .length;
    }
    final variables = <Variable<Object>>[
      Variable<String>(normalized),
    ];
    final whereSql =
        StringBuffer("deleted_at = '' AND lower(barcode) = ?");
    if (excludeProductId != null && excludeProductId.trim().isNotEmpty) {
      whereSql.write(' AND id <> ?');
      variables.add(Variable<String>(excludeProductId.trim()));
    }
    final row = await db.customSelect(
      'SELECT COUNT(*) AS value FROM products WHERE ${whereSql.toString()}',
      variables: variables,
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  static Future<int> countByCatalogItem(
    String type,
    CatalogItem item,
  ) async {
    if (type != 'category' && type != 'unit') return 0;
    final db = _businessDb();
    if (db == null) return 0;
    final column = type == 'category' ? 'category' : 'unit';
    final normalized = <String>{
      item.code.trim(),
      item.nameEn.trim(),
      item.nameAr.trim(),
    }.where((value) => value.isNotEmpty).map((value) => value.toLowerCase()).toList();
    if (normalized.isEmpty) return 0;
    final conditions = normalized
        .map((_) => 'LOWER(TRIM($column)) = ?')
        .join(' OR ');
    final row = await db.customSelect(
      'SELECT COUNT(*) AS value FROM products WHERE COALESCE(deleted_at, \'\') = \'\' AND ($conditions)',
      variables: <Variable<Object>>[
        for (final value in normalized) Variable<String>(value),
      ],
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  static Future<void> ensureDefaultPriceLists() async {
    final now = DateTime.now();
    await _upsertEntityJson(
      BusinessSqliteStore.priceListsKey,
      PriceList(
        id: 'retail',
        name: 'Retail',
        code: 'retail',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ).toJson(),
    );
    await _upsertEntityJson(
      BusinessSqliteStore.priceListsKey,
      PriceList(
        id: 'wholesale',
        name: 'Wholesale',
        code: 'wholesale',
        createdAt: now,
        updatedAt: now,
      ).toJson(),
    );
  }

  static Future<void> addOrUpdateCategory(
    BusinessSessionContext context,
    CatalogItem item,
  ) async {
    context.requirePermission(AppPermission.catalogManage);
    final normalizedNameEn = item.nameEn.trim();
    final normalizedNameAr = item.nameAr.trim();
    if (normalizedNameEn.isEmpty && normalizedNameAr.isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalized = item.copyWith(
      id: item.id.trim().isEmpty
          ? 'category_${DateTime.now().microsecondsSinceEpoch}'
          : item.id.trim(),
      nameEn: normalizedNameEn.isEmpty ? item.code.trim() : normalizedNameEn,
      nameAr: normalizedNameAr,
      code: item.code.trim(),
      updatedAt: DateTime.now(),
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: item.version <= 0 ? 1 : item.version,
      lastModifiedByDeviceId: context.deviceId,
      clearDeletedAt: true,
    );
    final current = await _readBusinessEntityList(
      BusinessSqliteStore.categoriesKey,
      (json) => CatalogItem.fromJson(json),
    );
    final duplicate = current.any((entry) {
      if (entry.id == normalized.id || entry.isDeleted) return false;
      return (normalizedNameEn.isNotEmpty &&
              entry.nameEn.trim().toLowerCase() ==
                  normalizedNameEn.toLowerCase()) ||
          (normalizedNameAr.isNotEmpty &&
              entry.nameAr.trim().toLowerCase() ==
                  normalizedNameAr.toLowerCase());
    });
    if (duplicate) {
      throw ArgumentError('This name already exists.');
    }
    await _upsertEntityJson(
      BusinessSqliteStore.categoriesKey,
      normalized.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'category',
      entityId: normalized.id,
      operation: 'create',
      payload: normalized.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.categoriesKey,
      refreshSummaries: false,
    );
  }

  static Future<void> addOrUpdateBrand(
    BusinessSessionContext context,
    CatalogItem item,
  ) async {
    context.requirePermission(AppPermission.catalogManage);
    final normalizedNameEn = item.nameEn.trim();
    final normalizedNameAr = item.nameAr.trim();
    if (normalizedNameEn.isEmpty && normalizedNameAr.isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalized = item.copyWith(
      id: item.id.trim().isEmpty
          ? 'brand_${DateTime.now().microsecondsSinceEpoch}'
          : item.id.trim(),
      nameEn: normalizedNameEn.isEmpty ? item.code.trim() : normalizedNameEn,
      nameAr: normalizedNameAr,
      code: item.code.trim(),
      updatedAt: DateTime.now(),
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: item.version <= 0 ? 1 : item.version,
      lastModifiedByDeviceId: context.deviceId,
      clearDeletedAt: true,
    );
    final current = await _readBusinessEntityList(
      BusinessSqliteStore.brandsKey,
      (json) => CatalogItem.fromJson(json),
    );
    final duplicate = current.any((entry) {
      if (entry.id == normalized.id || entry.isDeleted) return false;
      return (normalizedNameEn.isNotEmpty &&
              entry.nameEn.trim().toLowerCase() ==
                  normalizedNameEn.toLowerCase()) ||
          (normalizedNameAr.isNotEmpty &&
              entry.nameAr.trim().toLowerCase() ==
                  normalizedNameAr.toLowerCase());
    });
    if (duplicate) {
      throw ArgumentError('This name already exists.');
    }
    await _upsertEntityJson(BusinessSqliteStore.brandsKey, normalized.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'brand',
      entityId: normalized.id,
      operation: 'create',
      payload: normalized.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.brandsKey,
      refreshSummaries: false,
    );
  }

  static Future<void> addOrUpdateUnit(
    BusinessSessionContext context,
    CatalogItem item,
  ) async {
    context.requirePermission(AppPermission.catalogManage);
    final normalizedNameEn = item.nameEn.trim();
    final normalizedNameAr = item.nameAr.trim();
    if (normalizedNameEn.isEmpty && normalizedNameAr.isEmpty) {
      throw ArgumentError('English or Arabic name is required.');
    }
    final normalized = item.copyWith(
      id: item.id.trim().isEmpty
          ? 'unit_${DateTime.now().microsecondsSinceEpoch}'
          : item.id.trim(),
      nameEn: normalizedNameEn.isEmpty ? item.code.trim() : normalizedNameEn,
      nameAr: normalizedNameAr,
      code: item.code.trim(),
      updatedAt: DateTime.now(),
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: item.version <= 0 ? 1 : item.version,
      lastModifiedByDeviceId: context.deviceId,
      clearDeletedAt: true,
    );
    final current = await _readBusinessEntityList(
      BusinessSqliteStore.unitsKey,
      (json) => CatalogItem.fromJson(json),
    );
    final duplicate = current.any((entry) {
      if (entry.id == normalized.id || entry.isDeleted) return false;
      return (normalizedNameEn.isNotEmpty &&
              entry.nameEn.trim().toLowerCase() ==
                  normalizedNameEn.toLowerCase()) ||
          (normalizedNameAr.isNotEmpty &&
              entry.nameAr.trim().toLowerCase() ==
                  normalizedNameAr.toLowerCase());
    });
    if (duplicate) {
      throw ArgumentError('This name already exists.');
    }
    await _upsertEntityJson(BusinessSqliteStore.unitsKey, normalized.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'unit',
      entityId: normalized.id,
      operation: 'create',
      payload: normalized.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.unitsKey,
      refreshSummaries: false,
    );
  }

  static Future<void> replaceAndDeleteCatalogItem({
    required BusinessSessionContext context,
    required String type,
    required CatalogItem item,
    CatalogItem? replacement,
  }) async {
    context.requirePermission(AppPermission.catalogManage);
    if (type != 'category' && type != 'unit') {
      throw ArgumentError('Unsupported catalog type.');
    }
    final key = type == 'category'
        ? BusinessSqliteStore.categoriesKey
        : BusinessSqliteStore.unitsKey;
    final current = await _readBusinessEntityList(
      key,
      (json) => CatalogItem.fromJson(json),
    );
    final existing = current.where((entry) => !entry.isDeleted).toList();
    if (existing.length <= 1) {
      throw StateError('At least one item must remain.');
    }
    final targetIndex = current.indexWhere((entry) => entry.id == item.id);
    if (targetIndex == -1 || current[targetIndex].isDeleted) return;
    final target = current[targetIndex];
    final usageCount = await ProductRepository.countByCatalogItem(type, item);
    if (usageCount > 0) {
      if (replacement == null || replacement.id == item.id) {
        throw StateError('A replacement item is required.');
      }
      if (!existing.any((entry) => entry.id == replacement.id)) {
        throw StateError('Replacement item was not found.');
      }
    }

    final now = DateTime.now();
    if (usageCount > 0) {
      final effectiveReplacement = replacement!;
      final replacementValue = effectiveReplacement.displayName('en');
      const pageSize = 500;
      var offset = 0;
      while (true) {
        final page = await ProductRepository.queryPage(
          limit: pageSize,
          offset: offset,
          activeOnly: false,
        );
        if (page == null) break;
        for (final product in page.items) {
          if (product.isDeleted) continue;
          final currentValue = type == 'category' ? product.category : product.unit;
          final matches = _normalizeForCatalogComparison(currentValue) ==
              _normalizeForCatalogComparison(
                type == 'category' ? item.displayName('en') : item.displayName('en'),
              );
          if (!matches) continue;
          final updatedProduct = type == 'category'
              ? product.copyWith(
                  category: replacementValue,
                  updatedAt: now,
                  deviceId: context.deviceId,
                  syncStatus: 'pending',
                  version: product.version + 1,
                  lastModifiedByDeviceId: context.deviceId,
                )
              : product.copyWith(
                  unit: replacementValue,
                  updatedAt: now,
                  deviceId: context.deviceId,
                  syncStatus: 'pending',
                  version: product.version + 1,
                  lastModifiedByDeviceId: context.deviceId,
                );
          await _upsertEntityJson(
            BusinessSqliteStore.productsKey,
            updatedProduct.toJson(),
          );
          await _recordBusinessSyncChange(
            context: context,
            entityType: 'product',
            entityId: updatedProduct.id,
            operation: 'update',
            payload: updatedProduct.toJson(),
          );
        }
        if (page.items.length < pageSize) break;
        offset += page.items.length;
      }
    }

    final deleted = target.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: target.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(key, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: type,
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshEntityAndSync(context, key);
  }

  static String _normalizeForCatalogComparison(String value) =>
      value.trim().toLowerCase();

  static Future<void> setDefaultProductBasePrice(
    BusinessSessionContext context, {
    required String productId,
    required String unitId,
    required double amount,
    required String currencyCode,
  }) async {
    final existingProduct = await getById(productId);
    context.requirePermission(
      existingProduct == null ? AppPermission.productsCreate : AppPermission.productsEdit,
    );
    await ensureDefaultPriceLists();
    final now = DateTime.now();
    final price = ProductPrice(
      id:
          'pp_${productId}_${'retail'}_${unitId}_${now.microsecondsSinceEpoch}',
      productId: productId,
      priceListId: 'retail',
      unitId: unitId,
      baseCurrencyCode: currencyCode.toUpperCase(),
      baseAmount: amount,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.productPricesKey,
      price.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product_price',
      entityId: price.id,
      operation: 'upsert',
      payload: price.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.productPricesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> setProductPriceOverride({
    required BusinessSessionContext context,
    required String productPriceId,
    required String currencyCode,
    required double amount,
    ProductPriceOverrideMode mode = ProductPriceOverrideMode.fixed,
    bool isActive = true,
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (productPriceId.trim().isEmpty || normalizedCurrency.isEmpty) {
      throw ArgumentError('Product price and currency are required.');
    }
    final now = DateTime.now();
    final override = ProductPriceOverride(
      id:
          'ppo_${productPriceId}_${normalizedCurrency}_${now.microsecondsSinceEpoch}',
      productPriceId: productPriceId,
      currencyCode: normalizedCurrency,
      amount: amount,
      mode: mode,
      isActive: isActive,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.productPriceOverridesKey,
      override.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product_price_override',
      entityId: override.id,
      operation: 'upsert',
      payload: override.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.productPriceOverridesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> removeProductPriceOverride(
    BusinessSessionContext context,
    String productPriceId,
    String currencyCode,
  ) async {
    context.requirePermission(AppPermission.productsEdit);
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    final rows = await _readBusinessEntityList(
      BusinessSqliteStore.productPriceOverridesKey,
      (json) => ProductPriceOverride.fromJson(json),
    );
    final index = rows.indexWhere(
      (item) =>
          item.productPriceId == productPriceId &&
          item.currencyCode == normalizedCurrency,
    );
    if (index == -1) return;
    final now = DateTime.now();
    final updated = rows[index].copyWith(isActive: false, updatedAt: now);
    await _upsertEntityJson(
      BusinessSqliteStore.productPriceOverridesKey,
      updated.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product_price_override',
      entityId: updated.id,
      operation: 'update',
      payload: updated.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.productPriceOverridesKey,
      refreshSummaries: true,
    );
  }
}

class CustomerRepository {
  CustomerRepository._();

  static Future<BusinessQueryPage<Customer>?> queryPage({
    String query = '',
    int limit = 50,
    int offset = 0,
    bool includeWalkIn = false,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryCustomers(
      db,
      query: query,
      limit: limit,
      offset: offset,
      includeWalkIn: includeWalkIn,
    );
  }

  @Deprecated('Large-app mode: use queryPage() with LIMIT/OFFSET instead.')
  static Future<List<Customer>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readCustomers(db);
  }

  static Future<List<Customer>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.customersKey,
        (json) => Customer.fromJson(json),
      );

  static Future<int> countAll() async {
    final page = await queryPage(limit: 1);
    if (page != null) return page.totalCount;
    final customers = await listAll();
    return customers.where((customer) => !customer.isDeleted).length;
  }

  static Future<Customer?> getById(String id) async {
    if (id.trim() == _walkInCustomerId) {
      return Customer(
        id: _walkInCustomerId,
        name: _walkInCustomerName,
        phone: '',
        address: '',
      );
    }
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id && !item.isDeleted) return item;
      }
      return null;
    }
    return BusinessSqliteStore.readCustomerById(db, id);
  }

  static Future<Customer> addOrUpdateCustomer(
    BusinessSessionContext context,
    Customer customer,
  ) async {
    final existing = await getById(customer.id);
    final isCreate = existing == null;
    context.requirePermission(AppPermission.customersManage);
    final normalizedName = customer.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final db = _businessDb();
    if (db != null) {
      final row = await db.customSelect(
        'SELECT COUNT(*) AS value FROM customers WHERE deleted_at = \'\' AND lower(trim(name)) = ? AND id <> ?',
        variables: <Variable<Object>>[
          Variable<String>(normalizedName.toLowerCase()),
          Variable<String>(customer.id),
        ],
      ).getSingle();
      if (((row.data['value'] as num?)?.toInt() ?? 0) > 0) {
        throw ArgumentError('Customer name must be unique.');
      }
    } else {
      final customers = await listAll();
      final duplicate = customers.any(
        (item) =>
            !item.isDeleted &&
            item.id != customer.id &&
            item.name.trim().toLowerCase() == normalizedName.toLowerCase(),
      );
      if (duplicate) {
        throw ArgumentError('Customer name must be unique.');
      }
    }
    final now = DateTime.now();
    final updated = customer.copyWith(
      name: normalizedName,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: isCreate ? 1 : customer.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(BusinessSqliteStore.customersKey, updated.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'customer',
      entityId: updated.id,
      operation: isCreate ? 'create' : 'update',
      payload: updated.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.customersKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return updated;
  }

  static Future<void> deleteCustomer(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.customersManage);
    final existing = await getById(id);
    if (existing == null) return;
    final now = DateTime.now();
    final deleted = existing.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: existing.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(BusinessSqliteStore.customersKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'customer',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.customersKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }
}

class SupplierRepository {
  SupplierRepository._();

  static Future<BusinessQueryPage<Supplier>?> queryPage({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.querySuppliers(
      db,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  @Deprecated('Large-app mode: use queryPage() with LIMIT/OFFSET instead.')
  static Future<List<Supplier>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSuppliers(db);
  }

  static Future<List<Supplier>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.suppliersKey,
        (json) => Supplier.fromJson(json),
      );

  static Future<int> countAll() async {
    final page = await queryPage(limit: 1);
    if (page != null) return page.totalCount;
    final suppliers = await listAll();
    return suppliers.where((supplier) => !supplier.isDeleted).length;
  }

  static Future<Supplier?> getById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id && !item.isDeleted) return item;
      }
      return null;
    }
    return BusinessSqliteStore.readSupplierById(db, id);
  }

  static Future<Supplier> addOrUpdateSupplier(
    BusinessSessionContext context,
    Supplier supplier,
  ) async {
    final existing = await getById(supplier.id);
    final isCreate = existing == null;
    context.requirePermission(AppPermission.suppliersManage);
    final normalizedName = supplier.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }
    final db = _businessDb();
    if (db != null) {
      final row = await db.customSelect(
        'SELECT COUNT(*) AS value FROM suppliers WHERE deleted_at = \'\' AND lower(trim(name)) = ? AND id <> ?',
        variables: <Variable<Object>>[
          Variable<String>(normalizedName.toLowerCase()),
          Variable<String>(supplier.id),
        ],
      ).getSingle();
      if (((row.data['value'] as num?)?.toInt() ?? 0) > 0) {
        throw ArgumentError('Supplier name must be unique.');
      }
    } else {
      final suppliers = await listAll();
      final duplicate = suppliers.any(
        (item) =>
            !item.isDeleted &&
            item.id != supplier.id &&
            item.name.trim().toLowerCase() == normalizedName.toLowerCase(),
      );
      if (duplicate) {
        throw ArgumentError('Supplier name must be unique.');
      }
    }
    final now = DateTime.now();
    final updated = supplier.copyWith(
      name: normalizedName,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: isCreate ? 1 : supplier.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(BusinessSqliteStore.suppliersKey, updated.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'supplier',
      entityId: updated.id,
      operation: isCreate ? 'create' : 'update',
      payload: updated.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.suppliersKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return updated;
  }

  static Future<void> deleteSupplier(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.suppliersManage);
    final existing = await getById(id);
    if (existing == null) return;
    final now = DateTime.now();
    final deleted = existing.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: existing.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _saveBusinessRow(BusinessSqliteStore.suppliersKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'supplier',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.suppliersKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }
}

class SaleRepository {
  SaleRepository._();

  static Future<BusinessQueryPage<Sale>?> queryPage({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.querySales(
      db,
      query: query,
      status: status,
      customerId: customerId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  static Future<BusinessQueryPage<SaleSummary>?> querySummaryPage({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.querySaleSummaries(
      db,
      query: query,
      status: status,
      customerId: customerId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  @Deprecated('Large-app mode: use queryPage()/querySummaryPage() with LIMIT/OFFSET instead.')
  static Future<List<Sale>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSales(db);
  }

  static Future<List<Sale>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.salesKey,
        (json) => Sale.fromJson(json),
      );

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final page = await queryPage(limit: 1);
      if (page != null) return page.totalCount;
    }
    return _countBusinessEntityList(BusinessSqliteStore.salesKey);
  }

  static Future<Sale?> getById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }
    final results = await BusinessSqliteStore.readSalesByIds(db, <String>[id]);
    return results.isEmpty ? null : results.first;
  }

  static Future<List<SaleQuotation>?> getQuotations() async {
    final db = _businessDb();
    if (db == null) {
      return _readBusinessEntityList(
        BusinessSqliteStore.saleQuotationsKey,
        (json) => SaleQuotation.fromJson(json),
      );
    }
    return BusinessSqliteStore.readSaleQuotations(db);
  }

  static Future<List<DeliveryNote>?> getDeliveryNotes() async {
    final db = _businessDb();
    if (db == null) {
      return _readBusinessEntityList(
        BusinessSqliteStore.deliveryNotesKey,
        (json) => DeliveryNote.fromJson(json),
      );
    }
    return BusinessSqliteStore.readDeliveryNotes(db);
  }

  static Future<BusinessQueryPage<SaleQuotation>?> queryQuotationsPage({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.querySaleQuotations(
      db,
      query: query,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  static Future<BusinessQueryPage<DeliveryNote>?> queryDeliveryNotesPage({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryDeliveryNotes(
      db,
      query: query,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  static Future<DeliveryNote?> getDeliveryNoteBySaleId(String saleId) async {
    final db = _businessDb();
    if (db == null) {
      final notes = await getDeliveryNotes() ?? const <DeliveryNote>[];
      for (final note in notes) {
        if (note.saleId == saleId) return note;
      }
      return null;
    }
    return BusinessSqliteStore.readDeliveryNoteBySaleId(db, saleId);
  }

  static double _baseQuantityForSaleItem(SaleItem item) {
    final baseQty = item.baseQuantity;
    if (baseQty > 0) return baseQty;
    return item.quantity * item.conversionToBase;
  }

  static Future<List<SaleItem>> _normalizeSaleItems(
    BusinessSessionContext context,
    List<SaleItem> items,
    DateTime now, {
    required bool allowAutoCorrection,
    required bool mutateProducts,
    required String saleReferenceId,
    required String saleReferenceNo,
  }) async {
    final normalized = <SaleItem>[];
    for (var lineIndex = 0; lineIndex < items.length; lineIndex += 1) {
      final item = items[lineIndex];
      final product = await ProductRepository.getCoreById(item.productId);
      if (product == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
      final baseQty = _baseQuantityForSaleItem(item);
      if (baseQty <= 0 || item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid sale item values.');
      }
      final unitCost = item.unitCost > 0 ? item.unitCost : product.usdCost;
      var currentStock = product.stock;
      if (allowAutoCorrection && product.trackStock && currentStock < baseQty) {
        final shortage = baseQty - currentStock;
        final corrected = product.copyWith(
          stock: product.stock + shortage,
          updatedAt: now,
          deviceId: context.deviceId,
          syncStatus: 'pending',
          version: product.version + 1,
          lastModifiedByDeviceId: context.deviceId,
        );
        if (mutateProducts) {
          await _upsertEntityJson(
            BusinessSqliteStore.productsKey,
            corrected.toJson(),
          );
          await _recordBusinessSyncChange(
            context: context,
            entityType: 'product',
            entityId: corrected.id,
            operation: 'update',
            payload: corrected.toJson(),
          );
        }
        currentStock = corrected.stock;
        final correctionMovement = StockMovement(
          id: '$saleReferenceId-${item.productId}-auto-correction-$lineIndex',
          productId: item.productId,
          productName: item.productName,
          type: 'auto_correction',
          quantity: shortage,
          date: now,
          referenceId: saleReferenceId,
          referenceNo: saleReferenceNo,
          reason: 'Automatic inventory correction before sale',
          adjustmentCategory: 'auto_sale_correction',
          notes:
              'Created automatically because available stock was insufficient during POS sale.',
          unitCost: unitCost,
          createdAt: now,
          updatedAt: now,
          deviceId: context.deviceId,
          storeId: context.appIdentity.storeId,
          branchId: context.appIdentity.branchId,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.stockMovementsKey,
          correctionMovement.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'stock_movement',
          entityId: correctionMovement.id,
          operation: 'auto_correction',
          payload: correctionMovement.toJson(),
        );
      }
      if (product.trackStock && mutateProducts) {
        final nextProduct = product.copyWith(
          stock: currentStock - baseQty,
          updatedAt: now,
          deviceId: context.deviceId,
          syncStatus: 'pending',
          version: product.version + 1,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.productsKey,
          nextProduct.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'product',
          entityId: nextProduct.id,
          operation: 'update',
          payload: nextProduct.toJson(),
        );
        final saleMovement = StockMovement(
          id: '$saleReferenceId-${item.productId}-sale-$lineIndex',
          productId: item.productId,
          productName: item.productName,
          type: 'sale',
          quantity: -baseQty,
          date: now,
          referenceId: saleReferenceId,
          referenceNo: saleReferenceNo,
          reason: 'Sale invoice',
          unitCost: unitCost,
          createdAt: now,
          updatedAt: now,
          deviceId: context.deviceId,
          storeId: context.appIdentity.storeId,
          branchId: context.appIdentity.branchId,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.stockMovementsKey,
          saleMovement.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'stock_movement',
          entityId: saleMovement.id,
          operation: 'sale',
          payload: saleMovement.toJson(),
        );
      }
      normalized.add(
        SaleItem(
          productId: item.productId,
          productName: item.productName,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          unitName: item.unitName,
          baseQuantity: baseQty,
          conversionToBase: item.conversionToBase,
          unitCost: unitCost,
          costingMethodAtSale: item.costingMethodAtSale,
          costCurrency: item.costCurrency,
          costExchangeRate: item.costExchangeRate,
          costLayerConsumptions: item.costLayerConsumptions,
        ),
      );
    }
    return normalized;
  }

  static Future<Sale> createSale({
    required BusinessSessionContext context,
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
    context.requirePermission(AppPermission.salesCreate);
    if (items.isEmpty) {
      throw ArgumentError('Sale must contain at least one item.');
    }
    final cleanedDiscount = discount.isFinite
        ? discount.clamp(0, double.infinity).toDouble()
        : 0.0;
    final now = DateTime.now();
    final sequence = await _nextCounter(_invoiceCounterKey);
    final rawSubtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > rawSubtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    final saleItems = await _normalizeSaleItems(
      context,
      items,
      now,
      allowAutoCorrection: true,
      mutateProducts: true,
      saleReferenceId: 'sale_${_invoicePrefix(context)}_${sequence.toString().padLeft(6, '0')}',
      saleReferenceNo: 'INV-${_invoicePrefix(context)}-${sequence.toString().padLeft(6, '0')}',
    );
    final subtotal = saleItems.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final normalizedCustomerId =
        customerId.trim().isEmpty ? _walkInCustomerId : customerId.trim();
    final normalizedCustomerName = customerName.trim().isEmpty
        ? _walkInCustomerName
        : customerName.trim();
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    if (normalizedCustomerId == _walkInCustomerId &&
        normalizedPaymentMethod.toLowerCase() == 'credit') {
      throw ArgumentError('Walk-in customer sales cannot be credit.');
    }
    final total = (subtotal - cleanedDiscount).clamp(0, double.infinity).toDouble();
    final requestedStatus = paymentStatus.trim().toLowerCase();
    final normalizedPaymentStatus = normalizedPaymentMethod.toLowerCase() == 'credit'
        ? (requestedStatus == 'partial' ? 'partial' : 'credit')
        : (requestedStatus == 'credit'
            ? 'credit'
            : requestedStatus == 'partial'
                ? 'partial'
                : 'paid');
    final normalizedPaidAmount = (paidAmount ?? total).clamp(0, total).toDouble();
    final normalizedCashReceived = (cashReceivedAmount ??
            (normalizedPaymentMethod.toLowerCase() == 'cash' ? total : 0))
        .clamp(0, total)
        .toDouble();
    final sale = Sale(
      id: 'sale_${_invoicePrefix(context)}_${sequence.toString().padLeft(6, '0')}',
      invoiceNo: 'INV-${_invoicePrefix(context)}-${sequence.toString().padLeft(6, '0')}',
      customerName: normalizedCustomerName,
      customerId: normalizedCustomerId,
      date: now,
      status: 'Paid',
      items: saleItems,
      discount: cleanedDiscount,
      originalDiscount: originalDiscount ?? cleanedDiscount,
      discountCurrency: discountCurrency.trim().isEmpty ? 'USD' : discountCurrency.trim().toUpperCase(),
      discountExchangeRateAtEntry: discountExchangeRateAtEntry,
      paymentMethod: normalizedPaymentMethod,
      paymentStatus: normalizedPaymentStatus,
      invoiceCurrency: invoiceCurrency.trim().isEmpty ? 'USD' : invoiceCurrency.trim().toUpperCase(),
      paymentCurrency: paymentCurrency.trim().isEmpty ? 'USD' : paymentCurrency.trim().toUpperCase(),
      exchangeRateAtPayment: exchangeRateAtPayment ?? 1,
      baseCurrency: context.storeProfile.baseCurrency,
      exchangeRateAtInvoice: 1,
      transactionAmount: total,
      baseAmount: total,
      paidBaseAmount: normalizedPaidAmount,
      paidAmount: normalizedPaidAmount,
      cashReceivedAmount: normalizedCashReceived,
      paidAmountInPaymentCurrency: paidAmountInPaymentCurrency ?? normalizedPaidAmount,
      cashReceivedAmountInPaymentCurrency:
          cashReceivedAmountInPaymentCurrency ?? normalizedCashReceived,
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.salesKey, sale.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale',
      entityId: sale.id,
      operation: 'create',
      payload: sale.toJson(),
    );
    try {
      await AccountingService.recordSale(sale);
    } catch (_) {
      // Keep the sale flow operational if accounting posting is temporarily unavailable.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.salesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return sale;
  }

  static Future<SaleQuotation> createSaleQuotation({
    required BusinessSessionContext context,
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) async {
    context.requirePermission(AppPermission.salesCreate);
    if (items.isEmpty) {
      throw ArgumentError('Quotation must contain at least one item.');
    }
    final now = DateTime.now();
    final sequence = await _nextCounter('sale_quotation_counter_v1');
    final quotation = SaleQuotation(
      id: 'quotation_${_invoicePrefix(context)}_${sequence.toString().padLeft(6, '0')}',
      quotationNo: 'QUO-${_invoicePrefix(context)}-${sequence.toString().padLeft(6, '0')}',
      customerName:
          customerName.trim().isEmpty ? _walkInCustomerName : customerName.trim(),
      customerId: customerId.trim(),
      date: now,
      validUntil: validUntil,
      status: 'Draft',
      items: items,
      discount: discount.clamp(0, double.infinity).toDouble(),
      invoiceCurrency: invoiceCurrency.trim().isEmpty ? 'USD' : invoiceCurrency.trim().toUpperCase(),
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.saleQuotationsKey,
      quotation.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale_quotation',
      entityId: quotation.id,
      operation: 'create',
      payload: quotation.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.saleQuotationsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return quotation;
  }

  static Future<Sale> convertSaleQuotationToSale(
    BusinessSessionContext context,
    String quotationId,
  ) async {
    context.requirePermission(AppPermission.salesCreate);
    final quotations = await getQuotations();
    final quotation = quotations?.firstWhere(
      (item) => item.id == quotationId,
      orElse: () => throw ArgumentError('Quotation not found.'),
    );
    if (quotation == null) {
      throw ArgumentError('Quotation not found.');
    }
    if (quotation.isConverted) {
      throw StateError('Quotation already converted.');
    }
    final sale = await createSale(
      context: context,
      customerName: quotation.customerName,
      customerId: quotation.customerId,
      items: quotation.items,
      discount: quotation.discount,
      invoiceCurrency: quotation.invoiceCurrency,
      paymentMethod: 'Cash',
      paymentStatus: 'paid',
    );
    final now = DateTime.now();
    final convertedQuotation = quotation.copyWith(
      status: 'Converted',
      convertedSaleId: sale.id,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: quotation.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.saleQuotationsKey,
      convertedQuotation.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale_quotation',
      entityId: convertedQuotation.id,
      operation: 'convert',
      payload: convertedQuotation.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.saleQuotationsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return sale;
  }

  static Future<void> deleteSaleQuotation(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.salesCancel);
    final quotations = await getQuotations();
    final quotation = quotations?.firstWhere(
      (item) => item.id == id,
      orElse: () => throw ArgumentError('Quotation not found.'),
    );
    if (quotation == null) return;
    final now = DateTime.now();
    final deleted = quotation.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: quotation.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.saleQuotationsKey,
      deleted.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale_quotation',
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.saleQuotationsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<DeliveryNote> createDeliveryNoteFromSale(
    BusinessSessionContext context,
    String saleId,
  ) async {
    context.requirePermission(AppPermission.salesCreate);
    final sale = await getById(saleId);
    if (sale == null) throw ArgumentError('Sale not found.');
    final existing = await getDeliveryNoteBySaleId(saleId);
    if (existing != null) return existing;
    final now = DateTime.now();
    final sequence = await _nextCounter('delivery_note_counter_v1');
    final note = DeliveryNote(
      id: 'delivery_${_invoicePrefix(context)}_${sequence.toString().padLeft(6, '0')}',
      deliveryNo: 'DN-${_invoicePrefix(context)}-${sequence.toString().padLeft(6, '0')}',
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerName: sale.customerName,
      customerId: sale.customerId,
      date: now,
      status: 'Draft',
      items: sale.items,
      note: sale.note,
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.deliveryNotesKey, note.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'delivery_note',
      entityId: note.id,
      operation: 'create',
      payload: note.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.deliveryNotesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return note;
  }

  static Future<void> markDeliveryNoteDelivered(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.salesCancel);
    final notes = await getDeliveryNotes();
    final note = notes?.firstWhere(
      (item) => item.id == id,
      orElse: () => throw ArgumentError('Delivery note not found.'),
    );
    if (note == null) return;
    if (note.isDelivered) return;
    final now = DateTime.now();
    final updated = note.copyWith(
      status: 'Delivered',
      deliveredAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: note.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.deliveryNotesKey, updated.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'delivery_note',
      entityId: updated.id,
      operation: 'deliver',
      payload: updated.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.deliveryNotesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> deleteDeliveryNote(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.salesCancel);
    final notes = await getDeliveryNotes();
    final note = notes?.firstWhere(
      (item) => item.id == id,
      orElse: () => throw ArgumentError('Delivery note not found.'),
    );
    if (note == null) return;
    final now = DateTime.now();
    final deleted = note.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: note.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.deliveryNotesKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'delivery_note',
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.deliveryNotesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> returnSale(
    BusinessSessionContext context,
    String id, {
    bool restoreStock = true,
  }) async {
    context.requirePermission(AppPermission.salesCancel);
    final sale = await getById(id);
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) return;
    final now = DateTime.now();
    if (restoreStock) {
      for (var lineIndex = 0; lineIndex < sale.items.length; lineIndex += 1) {
        final item = sale.items[lineIndex];
        final product = await ProductRepository.getCoreById(item.productId);
        if (product == null || !product.trackStock) continue;
        final updatedProduct = product.copyWith(
          stock: product.stock + item.effectiveBaseQuantity,
          updatedAt: now,
          deviceId: context.deviceId,
          syncStatus: 'pending',
          version: product.version + 1,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.productsKey,
          updatedProduct.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'product',
          entityId: updatedProduct.id,
          operation: 'update',
          payload: updatedProduct.toJson(),
        );
        final movement = StockMovement(
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
          deviceId: context.deviceId,
          storeId: context.appIdentity.storeId,
          branchId: context.appIdentity.branchId,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.stockMovementsKey,
          movement.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'sale_return',
          payload: movement.toJson(),
        );
      }
    }

    final returnedSale = sale.copyWith(
      status: 'Returned',
      paymentStatus: 'returned',
      paidAmount: 0,
      cashReceivedAmount: 0,
      paidAmountInPaymentCurrency: 0,
      cashReceivedAmountInPaymentCurrency: 0,
      paidBaseAmount: 0,
      exchangeDifferenceAmount: 0,
      note: 'Returned on ${now.toIso8601String()}',
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: sale.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.salesKey, returnedSale.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale',
      entityId: returnedSale.id,
      operation: 'return',
      payload: returnedSale.toJson(),
    );
    try {
      await AccountingService.reverseEntryForReference(
        referenceType: 'sale',
        referenceId: sale.id,
        reason: 'Sale returned',
        createdBy: context.deviceId,
      );
    } catch (_) {
      // Best effort: the operational return should still complete.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.salesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> cancelSale(
    BusinessSessionContext context,
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) async {
    context.requirePermission(AppPermission.salesCancel);
    final sale = await getById(id);
    if (sale == null) {
      throw ArgumentError('Sale not found.');
    }
    if (sale.isCancelled) return;
    final now = DateTime.now();
    if (restoreStock) {
      for (var lineIndex = 0; lineIndex < sale.items.length; lineIndex += 1) {
        final item = sale.items[lineIndex];
        final product = await ProductRepository.getCoreById(item.productId);
        if (product == null || !product.trackStock) continue;
        final updatedProduct = product.copyWith(
          stock: product.stock + item.effectiveBaseQuantity,
          updatedAt: now,
          deviceId: context.deviceId,
          syncStatus: 'pending',
          version: product.version + 1,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.productsKey,
          updatedProduct.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'product',
          entityId: updatedProduct.id,
          operation: 'update',
          payload: updatedProduct.toJson(),
        );
        final movement = StockMovement(
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
          deviceId: context.deviceId,
          storeId: context.appIdentity.storeId,
          branchId: context.appIdentity.branchId,
          lastModifiedByDeviceId: context.deviceId,
        );
        await _upsertEntityJson(
          BusinessSqliteStore.stockMovementsKey,
          movement.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'sale_restore',
          payload: movement.toJson(),
        );
      }
    }
    final cancelledSale = sale.copyWith(
      status: status,
      paymentStatus: 'cancelled',
      paidAmount: 0,
      cashReceivedAmount: 0,
      paidAmountInPaymentCurrency: 0,
      cashReceivedAmountInPaymentCurrency: 0,
      paidBaseAmount: 0,
      exchangeDifferenceAmount: 0,
      note: 'Stock restored on ${now.toIso8601String()}',
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: sale.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.salesKey, cancelledSale.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'sale',
      entityId: cancelledSale.id,
      operation: 'cancel',
      payload: cancelledSale.toJson(),
    );
    try {
      await AccountingService.reverseEntryForReference(
        referenceType: 'sale',
        referenceId: sale.id,
        reason: status.trim().isEmpty ? 'Sale cancelled' : status.trim(),
        createdBy: context.deviceId,
      );
    } catch (_) {
      // Best effort: the operational cancellation should still complete.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.salesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> deleteSale(
    BusinessSessionContext context,
    String id, {
    bool restoreStock = true,
  }) async {
    await cancelSale(context, id, status: 'Cancelled', restoreStock: restoreStock);
  }
}

class ExpenseRepository {
  ExpenseRepository._();

  static Future<BusinessQueryPage<Expense>?> queryPage({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryExpenses(
      db,
      query: query,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  @Deprecated('Large-app mode: use queryPage() with LIMIT/OFFSET instead.')
  static Future<List<Expense>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readExpenses(db);
  }

  static Future<List<Expense>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.expensesKey,
        (json) => Expense.fromJson(json),
      );

  static Future<Expense?> getById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }
    final rows = await BusinessSqliteStore.readExpenses(db);
    for (final expense in rows) {
      if (expense.id == id) return expense;
    }
    return null;
  }

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final page = await queryPage(limit: 1);
      if (page != null) return page.totalCount;
    }
    return _countBusinessEntityList(BusinessSqliteStore.expensesKey);
  }

  static Future<double?> sumPosted({
    String query = '',
    String status = 'all',
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.sumPostedExpenses(
      db,
      query: query,
      status: status,
    );
  }

  static Future<Map<String, Object?>?> buildOverview({
    String query = '',
    String status = 'all',
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildExpensesOverview(
      db,
      query: query,
      status: status,
    );
  }

  static Future<Map<String, Object?>?> readCatalogUsage() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readExpenseCatalogUsage(db);
  }

  static Future<void> _writeExpenseLedgerEntries(
    BusinessSessionContext context,
    Expense expense,
    DateTime now, {
    required bool reversal,
    String reason = '',
  }) async {
    final accountId = expense.id.trim();
    if (accountId.isEmpty || expense.amount <= 0) return;
    final accountName =
        expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
    final currency = expense.originalCurrency.trim().isEmpty
        ? 'USD'
        : expense.originalCurrency.trim().toUpperCase();
    final noteSuffix = reason.trim().isEmpty
        ? (reversal ? 'cancelled expense' : accountName)
        : reason.trim();
    final debitTx = AccountTransaction(
      id: reversal
          ? '${expense.id}-expense-debit-reversal'
          : '${expense.id}-expense-debit',
      accountType: 'supplier',
      accountId: accountId,
      accountName: accountName,
      date: reversal ? now : expense.date,
      type: reversal ? 'cancel' : 'expense',
      referenceId: expense.id,
      referenceNo: accountName,
      debit: reversal ? 0 : expense.amount,
      credit: reversal ? expense.amount : 0,
      currency: currency,
      note: reversal
          ? 'Reverse expense debit for $noteSuffix'
          : 'Expense ${expense.title}',
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    final creditTx = AccountTransaction(
      id: reversal
          ? '${expense.id}-expense-credit-reversal'
          : '${expense.id}-expense-credit',
      accountType: 'supplier',
      accountId: accountId,
      accountName: accountName,
      date: reversal ? now : expense.date,
      type: reversal ? 'paymentReversal' : 'paymentPaid',
      paymentMethod: 'Cash',
      referenceId: expense.id,
      referenceNo: accountName,
      debit: reversal ? expense.amount : 0,
      credit: reversal ? 0 : expense.amount,
      currency: currency,
      note: reversal
          ? 'Reverse expense payment for $noteSuffix'
          : 'Expense settlement ${expense.title}',
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.accountTransactionsKey,
      debitTx.toJson(),
    );
    await _upsertEntityJson(
      BusinessSqliteStore.accountTransactionsKey,
      creditTx.toJson(),
    );
  }

  static Future<Expense> addOrUpdateExpense(
    BusinessSessionContext context,
    Expense expense,
  ) async {
    context.requirePermission(AppPermission.expensesManage);
    if (expense.title.trim().isEmpty ||
        expense.category.trim().isEmpty ||
        !expense.amount.isFinite ||
        expense.amount <= 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final existing = await getById(expense.id);
    if (existing != null) {
      if (existing.isPosted) {
        throw StateError('Posted expenses cannot be edited. Cancel them first.');
      }
      if (existing.isCancelled) {
        throw StateError('Cancelled expenses cannot be edited.');
      }
    }
    final now = DateTime.now();
    final normalized = expense.copyWith(
      status: existing == null ? 'Draft' : expense.status,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: existing == null ? 1 : existing.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.expensesKey,
      normalized.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'expense',
      entityId: normalized.id,
      operation: existing == null ? 'create' : 'update',
      payload: normalized.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.expensesKey,
      refreshSummaries: true,
    );
    return normalized;
  }

  static Future<void> postExpense(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.expensesManage);
    final expense = await getById(id);
    if (expense == null) {
      throw ArgumentError('Expense not found.');
    }
    if (expense.isPosted || expense.isCancelled) return;
    final now = DateTime.now();
    final posted = expense.copyWith(
      status: 'Posted',
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: expense.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.expensesKey, posted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'expense',
      entityId: posted.id,
      operation: 'post',
      payload: posted.toJson(),
    );
    await _writeExpenseLedgerEntries(
      context,
      posted,
      now,
      reversal: false,
    );
    try {
      await AccountingService.recordExpense(posted);
    } catch (_) {
      // Ledger posting is best-effort here; SQLite remains authoritative.
    }
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.expensesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> deleteDraftExpense(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.expensesManage);
    final expense = await getById(id);
    if (expense == null) return;
    if (expense.isPosted) {
      throw StateError('Posted expenses cannot be deleted. Cancel them first.');
    }
    if (expense.isCancelled) {
      throw StateError('Cancelled expenses require permanent delete permission.');
    }
    final now = DateTime.now();
    final deleted = expense.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: expense.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.expensesKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'expense',
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.expensesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> cancelExpense(
    BusinessSessionContext context,
    String id, {
    String reason = '',
  }) async {
    context.requirePermission(AppPermission.expensesManage);
    final expense = await getById(id);
    if (expense == null) {
      throw ArgumentError('Expense not found.');
    }
    if (expense.isCancelled) return;
    if (!expense.isPosted) {
      throw StateError(
        'Only posted expenses can be cancelled. Delete draft expenses instead.',
      );
    }
    final now = DateTime.now();
    final cancelled = expense.copyWith(
      status: 'Cancelled',
      cancelReason: reason.trim(),
      cancelledAt: now,
      cancelledByDeviceId: context.deviceId,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: expense.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(
      BusinessSqliteStore.expensesKey,
      cancelled.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'expense',
      entityId: cancelled.id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _writeExpenseLedgerEntries(
      context,
      cancelled,
      now,
      reversal: true,
      reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
    );
    try {
      await AccountingService.reverseEntryForReference(
        referenceType: 'expense',
        referenceId: expense.id,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
        createdBy: context.deviceId,
      );
    } catch (_) {
      // Ignore ledger reversal failures in SQLite-first mode.
    }
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.expensesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> permanentlyDeleteCancelledExpense(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.databaseManage);
    final expense = await getById(id);
    if (expense == null) return;
    if (!expense.isCancelled) {
      throw StateError('Only cancelled expenses can be permanently deleted.');
    }
    final now = DateTime.now();
    final deleted = expense.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: expense.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.expensesKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'expense',
      entityId: deleted.id,
      operation: 'permanent_delete',
      payload: deleted.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.expensesKey,
      refreshSummaries: true,
    );
  }

  static Future<void> deleteExpense(
    BusinessSessionContext context,
    String id,
  ) =>
      deleteDraftExpense(context, id);
}

class PurchaseRepository {
  PurchaseRepository._();

  static Future<BusinessQueryPage<Purchase>?> queryPage({
    String query = '',
    String status = 'all',
    String supplierId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryPurchases(
      db,
      query: query,
      status: status,
      supplierId: supplierId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  static Future<Purchase?> getById(String id) async {
    final db = _businessDb();
    if (db == null) {
      final items = await listAll();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }
    final results =
        await BusinessSqliteStore.readPurchasesByIds(db, <String>[id]);
    return results.isEmpty ? null : results.first;
  }

  static Future<Map<String, Object?>?> buildOverview({
    DateTime? reference,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildPurchasesOverview(
      db,
      reference: reference ?? DateTime.now(),
    );
  }

  @Deprecated('Large-app mode: use queryPage() with LIMIT/OFFSET instead.')
  static Future<List<Purchase>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readPurchases(db);
  }

  static Future<List<Purchase>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.purchasesKey,
        (json) => Purchase.fromJson(json),
      );

  static Future<List<SupplierPurchasePrice>> purchasePriceHistoryForProduct(
    String productId,
  ) async {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) return const <SupplierPurchasePrice>[];
    final purchases = await listAll();
    final rows = <SupplierPurchasePrice>[];
    for (final purchase in purchases) {
      if (purchase.isDeleted || purchase.isCancelled) continue;
      for (final item in purchase.items) {
        if (item.productId.trim() != cleanProductId) continue;
        rows.add(
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
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  static Future<List<SupplierProductPrice>> supplierProductPricesForProduct(
    String productId,
  ) async {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) return const <SupplierProductPrice>[];
    final rows = await _supplierProductPrices();
    final filtered = rows
        .where((item) => !item.isDeleted && item.productId == cleanProductId)
        .toList(growable: false)
      ..sort((a, b) {
        if (a.isPreferred != b.isPreferred) return a.isPreferred ? -1 : 1;
        return a.cost.compareTo(b.cost);
      });
    return filtered;
  }

  static Future<List<SupplierProductPrice>> supplierProductPricesForSupplier(
    String supplierId,
  ) async {
    final cleanSupplierId = supplierId.trim();
    if (cleanSupplierId.isEmpty) return const <SupplierProductPrice>[];
    final rows = await _supplierProductPrices();
    final filtered = rows
        .where((item) => !item.isDeleted && item.supplierId == cleanSupplierId)
        .toList(growable: false)
      ..sort((a, b) => a.productId.compareTo(b.productId));
    return filtered;
  }

  static Future<SupplierProductPrice?> supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) async {
    final rows = await supplierProductPricesForProduct(productId);
    for (final row in rows) {
      if (row.supplierId == supplierId.trim()) return row;
    }
    return null;
  }

  static Future<SupplierProductPrice?> preferredSupplierProductPriceForProduct(
    String productId,
  ) async {
    final rows = await supplierProductPricesForProduct(productId);
    for (final row in rows) {
      if (row.isPreferred) return row;
    }
    return rows.isEmpty ? null : rows.first;
  }

  static Future<SupplierProductPrice?> bestPriceSupplierProductPriceForProduct(
    String productId,
  ) async {
    final rows = await supplierProductPricesForProduct(productId);
    if (rows.isEmpty) return null;
    final sorted = rows.toList(growable: false)
      ..sort((a, b) => a.cost.compareTo(b.cost));
    return sorted.first;
  }

  static Future<SupplierProductPrice?> fastestSupplierProductPriceForProduct(
    String productId,
  ) async {
    final rows = (await supplierProductPricesForProduct(productId))
        .where((item) => item.leadTimeDays != null)
        .toList(growable: false)
      ..sort((a, b) => a.leadTimeDays!.compareTo(b.leadTimeDays!));
    return rows.isEmpty ? null : rows.first;
  }

  static Future<double?> lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  }) async {
    final history = await purchasePriceHistoryForProduct(productId);
    for (final row in history) {
      if (row.supplierId == supplierId.trim()) return row.unitCost;
    }
    return null;
  }

  static Future<double?> lastPurchasePriceForProduct(String productId) async {
    final history = await purchasePriceHistoryForProduct(productId);
    return history.isEmpty ? null : history.first.unitCost;
  }

  static Future<PurchaseItem?> lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  }) async {
    final cleanProductId = productId.trim();
    final cleanSupplierId = supplierId.trim();
    if (cleanProductId.isEmpty || cleanSupplierId.isEmpty) {
      return null;
    }
    final purchases = await listAll();
    final sortedPurchases = purchases
        .where(
          (purchase) =>
              !purchase.isDeleted &&
              !purchase.isCancelled &&
              purchase.supplierId.trim() == cleanSupplierId,
        )
        .toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId.trim() == cleanProductId) return item;
      }
    }
    return null;
  }

  static Future<PurchaseItem?> lastPurchaseItemForProduct(
    String productId,
  ) async {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) return null;
    final purchases = await listAll();
    final sortedPurchases = purchases
        .where((purchase) => !purchase.isDeleted && !purchase.isCancelled)
        .toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId.trim() == cleanProductId) return item;
      }
    }
    return null;
  }

  static Future<double> averagePurchaseCostForProduct(String productId) async {
    final history = await purchasePriceHistoryForProduct(productId);
    if (history.isEmpty) return 0;
    var totalQty = 0.0;
    var totalCost = 0.0;
    for (final row in history) {
      totalQty += row.quantity;
      totalCost += row.quantity * row.unitCost;
    }
    return totalQty <= 0 ? 0 : totalCost / totalQty;
  }

  static Future<int> supplierCountForProduct(String productId) async {
    final history = await purchasePriceHistoryForProduct(productId);
    return history.map((item) => item.supplierId.trim()).where((id) => id.isNotEmpty).toSet().length;
  }

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final page = await queryPage(limit: 1);
      if (page != null) return page.totalCount;
    }
    return _countBusinessEntityList(BusinessSqliteStore.purchasesKey);
  }

  static Future<void> _applyPurchaseReceipt(
    BusinessSessionContext context,
    Purchase purchase,
    DateTime now, {
    required String operation,
    required bool updateProducts,
    required bool isReturn,
    required bool isCancel,
    String reason = '',
  }) async {
    final movements = <StockMovement>[];
    final updatedProducts = <Product>[];
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final product = await ProductRepository.getCoreById(item.productId);
      if (product == null || !product.trackStock) continue;
      final delta = isReturn || isCancel ? -item.baseQuantity : item.baseQuantity;
      final nextStock = product.stock + delta;
      final weightedCost = product.stock + item.baseQuantity <= 0
          ? item.unitCostPerBase
          : ((product.stock * product.usdCost) +
                  (item.baseQuantity * item.unitCostPerBase)) /
              (product.stock + item.baseQuantity);
      final updatedProduct = product.copyWith(
        stock: nextStock,
        cost: isReturn || isCancel ? product.cost : weightedCost,
        usdCost: isReturn || isCancel ? product.usdCost : weightedCost,
        originalCost: isReturn || isCancel ? product.originalCost : weightedCost,
        costCurrency: 'USD',
        updatedAt: now,
        deviceId: context.deviceId,
        syncStatus: 'pending',
        version: product.version + 1,
        lastModifiedByDeviceId: context.deviceId,
      );
      updatedProducts.add(updatedProduct);
      movements.add(
        StockMovement(
          id: '${purchase.id}-$lineIndex-${item.productId}-$operation',
          productId: item.productId,
          productName: item.productName,
          type: operation,
          quantity: delta,
          date: now,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          reason: reason.isEmpty
              ? (isReturn
                  ? 'Purchase returned'
                  : isCancel
                      ? 'Purchase cancelled'
                      : 'Purchase received')
              : reason,
          unitCost: item.unitCostPerBase,
          createdAt: now,
          updatedAt: now,
          deviceId: context.deviceId,
          storeId: context.appIdentity.storeId,
          branchId: context.appIdentity.branchId,
          lastModifiedByDeviceId: context.deviceId,
        ),
      );
    }

    if (updateProducts) {
      for (final product in updatedProducts) {
        await _upsertEntityJson(
          BusinessSqliteStore.productsKey,
          product.toJson(),
        );
        await _recordBusinessSyncChange(
          context: context,
          entityType: 'product',
          entityId: product.id,
          operation: 'update',
          payload: product.toJson(),
        );
      }
    }
    for (final movement in movements) {
      await _upsertEntityJson(
        BusinessSqliteStore.stockMovementsKey,
        movement.toJson(),
      );
      await _recordBusinessSyncChange(
        context: context,
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: operation,
        payload: movement.toJson(),
      );
    }
  }

  static Future<Purchase> createPurchase({
    required BusinessSessionContext context,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
  }) async {
    context.requirePermission(AppPermission.suppliersManage);
    if (items.isEmpty) {
      throw ArgumentError('Purchase must contain at least one item.');
    }
    for (final item in items) {
      if (item.quantity <= 0 || item.conversionToBase <= 0 || item.unitCost < 0) {
        throw ArgumentError('Invalid purchase item values.');
      }
      final product = await ProductRepository.getCoreById(item.productId);
      if (product == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final sequence = await _nextCounter(_purchaseCounterKey);
    final now = DateTime.now();
    final purchaseTotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final normalizedPaymentStatus = paymentStatus.trim().toLowerCase() == 'credit'
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
      id: 'purchase_${_purchasePrefix(context)}_${sequence.toString().padLeft(6, '0')}',
      purchaseNo: 'PO-${_purchasePrefix(context)}-${sequence.toString().padLeft(6, '0')}',
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
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );

    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, purchase.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: purchase.id,
      operation: 'create',
      payload: purchase.toJson(),
    );
    if (receiveNow) {
      await _applyPurchaseReceipt(
        context,
        purchase,
        now,
        operation: 'purchase_receive',
        updateProducts: true,
        isReturn: false,
        isCancel: false,
      );
    }
    try {
      await AccountingService.recordPurchase(purchase);
    } catch (_) {
      // Keep the purchase flow operational if accounting posting is temporarily unavailable.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    if (receiveNow) {
      await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
      await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    }
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return purchase;
  }

  static Future<void> receivePurchase(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.suppliersManage);
    final purchase = await getById(id);
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isReceived || purchase.isCancelled) return;
    final now = DateTime.now();
    final received = purchase.copyWith(
      status: 'Received',
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: purchase.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, received.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: received.id,
      operation: 'receive',
      payload: received.toJson(),
    );
    await _applyPurchaseReceipt(
      context,
      received,
      now,
      operation: 'purchase_receive',
      updateProducts: true,
      isReturn: false,
      isCancel: false,
    );
    try {
      await AccountingService.recordPurchase(received);
    } catch (_) {
      // Keep the receive flow operational if accounting posting is temporarily unavailable.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> deleteDraftPurchase(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.suppliersManage);
    final purchase = await getById(id);
    if (purchase == null) return;
    if (purchase.isReceived) {
      throw StateError('Received purchase invoices cannot be deleted. Cancel them first.');
    }
    if (purchase.isCancelled) {
      throw StateError('Cancelled purchase invoices require permanent delete permission.');
    }
    final now = DateTime.now();
    final deleted = purchase.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: purchase.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> permanentlyDeleteCancelledPurchase(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.databaseManage);
    final purchase = await getById(id);
    if (purchase == null) return;
    if (purchase.status.toLowerCase() != 'cancelled') {
      throw StateError('Only cancelled purchase invoices can be permanently deleted.');
    }
    final now = DateTime.now();
    final deleted = purchase.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: purchase.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, deleted.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: id,
      operation: 'permanent_delete',
      payload: deleted.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> returnPurchase(
    BusinessSessionContext context,
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    context.requirePermission(AppPermission.suppliersManage);
    final purchase = await getById(id);
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be returned. Delete draft invoices instead.',
      );
    }
    final now = DateTime.now();
    if (reverseStock) {
      await _applyPurchaseReceipt(
        context,
        purchase,
        now,
        operation: 'purchase_return',
        updateProducts: true,
        isReturn: true,
        isCancel: false,
        reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
      );
    }
    final returned = purchase.copyWith(
      status: 'Returned',
      cancelledAt: now,
      cancelledByDeviceId: context.deviceId,
      cancelReason: reason.trim(),
      reversalApplied: true,
      note: 'Returned on ${now.toIso8601String()}',
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: purchase.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, returned.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: id,
      operation: 'return',
      payload: returned.toJson(),
    );
    try {
      await AccountingService.reverseEntryForReference(
        referenceType: 'purchase',
        referenceId: purchase.id,
        reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
        createdBy: context.deviceId,
      );
    } catch (_) {
      // Best effort: the operational return should still complete.
    }
    final tx = AccountTransaction(
      id: '${purchase.id}-purchase-return',
      accountType: 'supplier',
      accountId: purchase.supplierId,
      accountName: purchase.supplierName,
      date: now,
      type: 'purchaseReturn',
      referenceId: purchase.id,
      referenceNo: purchase.purchaseNo,
      debit: purchase.subtotal,
      credit: 0,
      note: reason.trim().isEmpty ? 'Purchase return ${purchase.purchaseNo}' : reason.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.accountTransactionsKey, tx.toJson());
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.accountTransactionsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> cancelPurchase(
    BusinessSessionContext context,
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    context.requirePermission(AppPermission.suppliersManage);
    final purchase = await getById(id);
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be cancelled. Delete draft invoices instead.',
      );
    }
    final now = DateTime.now();
    if (reverseStock) {
      await _applyPurchaseReceipt(
        context,
        purchase,
        now,
        operation: 'purchase_cancel',
        updateProducts: true,
        isReturn: false,
        isCancel: true,
        reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
      );
    }
    final cancelled = purchase.copyWith(
      status: 'Cancelled',
      cancelledAt: now,
      cancelledByDeviceId: context.deviceId,
      cancelReason: reason.trim(),
      reversalApplied: true,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: purchase.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.purchasesKey, cancelled.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'purchase',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    try {
      await AccountingService.reverseEntryForReference(
        referenceType: 'purchase',
        referenceId: purchase.id,
        reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
        createdBy: context.deviceId,
      );
    } catch (_) {
      // Best effort: the operational cancellation should still complete.
    }
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.purchasesKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<List<SupplierProductPrice>> _supplierProductPrices() async {
    final db = _businessDb();
    if (db != null) {
      final rows = await BusinessSqliteStore.readSupplierProductPrices(db);
      return rows;
    }
    return _readBusinessEntityList(
      BusinessSqliteStore.supplierProductPricesKey,
      (json) => SupplierProductPrice.fromJson(json),
    );
  }
}

class InventoryRepository {
  InventoryRepository._();

  static Future<Map<String, Object?>?> buildOverview() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildInventoryOverview(db);
  }

  static Future<void> setInventoryCostingMethod(
    BusinessSessionContext context,
    InventoryCostingMethod method, {
    String reason = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    final now = DateTime.now();
    final currentMethodCode =
        LocalDatabaseService.getString(BusinessSqliteStore.inventoryCostingMethodKey) ??
            InventoryCostingMethod.weightedAverage.code;
    final currentMethod =
        InventoryCostingMethodJson.fromCode(currentMethodCode);
    final historyRaw = LocalDatabaseService.getString(
      BusinessSqliteStore.costingMethodHistoryKey,
    );
    final history = historyRaw == null || historyRaw.trim().isEmpty
        ? <CostingMethodHistory>[]
        : (jsonDecode(historyRaw) as List<dynamic>)
            .whereType<Map>()
            .map((item) => CostingMethodHistory.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false);
    if (currentMethod == method && history.isNotEmpty) {
      return;
    }
    if (history.isNotEmpty) {
      final openIndex =
          history.indexWhere((item) => item.effectiveTo == null);
      if (openIndex != -1) {
        history[openIndex] = history[openIndex]
            .copyWith(effectiveTo: now, updatedAt: now);
      }
    }
    final nextHistory = List<CostingMethodHistory>.from(history)
      ..add(
        CostingMethodHistory(
          id: 'costing_${now.microsecondsSinceEpoch}',
          method: method,
          effectiveFrom: now,
          reason: reason.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    await LocalDatabaseService.setString(
      BusinessSqliteStore.inventoryCostingMethodKey,
      method.code,
    );
    await LocalDatabaseService.setString(
      BusinessSqliteStore.costingMethodHistoryKey,
      jsonEncode(nextHistory.map((item) => item.toJson()).toList()),
    );
    await context.refreshAfterDatabaseChange(
      BusinessSqliteStore.inventoryCostingMethodKey,
    );
    await context.refreshAfterDatabaseChange(
      BusinessSqliteStore.costingMethodHistoryKey,
    );
  }

  static Future<BusinessQueryPage<StockMovement>?> queryStockMovements({
    String query = '',
    String movementType = '',
    bool lossOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryStockMovements(
      db,
      query: query,
      movementType: movementType,
      lossOnly: lossOnly,
      limit: limit,
      offset: offset,
    );
  }

  @Deprecated('Large-app mode: use queryStockMovements() with LIMIT/OFFSET instead.')
  static Future<List<StockMovement>?> getStockMovements() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readStockMovements(db);
  }

  static Future<List<StockMovement>> listStockMovements() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.stockMovementsKey,
        (json) => StockMovement.fromJson(json),
      );

  static Future<int> countStockMovements() async {
    final db = _businessDb();
    if (db != null) {
      final page = await queryStockMovements(limit: 1);
      if (page != null) return page.totalCount;
    }
    return _countBusinessEntityList(BusinessSqliteStore.stockMovementsKey);
  }

  static Future<List<InventoryCountSession>?> getInventoryCounts() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readInventoryCounts(db);
  }

  static Future<InventoryCountSession?> createInventoryCountSession({
    String notes = '',
  }) async {
    final db = _businessDb();
    if (db == null) return null;

    final existingSessions = await getInventoryCounts() ?? const <InventoryCountSession>[];
    if (existingSessions.any((session) => session.isOpen)) {
      throw StateError('There is already an open inventory count session.');
    }

    const pageSize = 500;
    var offset = 0;
    final trackedProducts = <Product>[];
    while (true) {
      final page = await ProductRepository.queryPage(
        limit: pageSize,
        offset: offset,
        stockTrackedOnly: true,
        activeOnly: true,
      );
      if (page == null) return null;
      trackedProducts.addAll(page.items.where((item) => !item.isDeleted));
      if (page.items.length < pageSize) break;
      offset += page.items.length;
    }

    final warehouses = await getWarehouses() ?? const <Warehouse>[];
    final defaultWarehouse = warehouses.firstWhere(
      (warehouse) => warehouse.isDefault && !warehouse.isDeleted,
      orElse: () => warehouses.isNotEmpty
          ? warehouses.first
          : Warehouse(
              id: Warehouse.defaultId,
              name: Warehouse.defaultName,
              isDefault: true,
            ),
    );

    final now = DateTime.now();
    final session = InventoryCountSession(
      id: now.microsecondsSinceEpoch.toString(),
      countNo: 'CNT-${now.microsecondsSinceEpoch}',
      createdAt: now,
      createdBy: '',
      warehouseId: defaultWarehouse.id,
      warehouseName: defaultWarehouse.name,
      notes: notes.trim(),
      lines: trackedProducts
          .map(
            (product) => InventoryCountLine(
              productId: product.id,
              productName: product.name,
              productCode: product.code,
              snapshotStock: product.stock,
            ),
          )
          .toList(growable: false),
    );
    await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
      BusinessSqliteStore.inventoryCountsKey,
      session.toJson(),
    );
    return session;
  }

  static Future<InventoryCountSession?> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) async {
    if (countedQty < 0) {
      throw ArgumentError('Counted quantity cannot be negative.');
    }
    final sessions = await getInventoryCounts();
    if (sessions == null) return null;
    final sessionIndex = sessions.indexWhere((item) => item.id == sessionId);
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = sessions[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be edited.');
    }
    final lineIndex = session.lines.indexWhere((item) => item.productId == productId);
    if (lineIndex == -1) {
      throw ArgumentError('Product is not part of this count session.');
    }
    final now = DateTime.now();
    final lines = List<InventoryCountLine>.from(session.lines);
    lines[lineIndex] = lines[lineIndex].copyWith(
      countedQty: countedQty,
      countedAt: now,
      countedBy: '',
      note: note.trim(),
    );
    final updated = session.copyWith(lines: lines, updatedAt: now);
    await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
      BusinessSqliteStore.inventoryCountsKey,
      updated.toJson(),
    );
    return updated;
  }

  static Future<InventoryCountSession?> approveInventoryCount(
    String sessionId,
  ) async {
    final sessions = await getInventoryCounts();
    if (sessions == null) return null;
    final sessionIndex = sessions.indexWhere((item) => item.id == sessionId);
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = sessions[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be approved.');
    }
    final countedLines =
        session.lines.where((line) => line.isCounted).toList(growable: false);
    if (countedLines.isEmpty) {
      throw StateError('No counted products to approve.');
    }

    final now = DateTime.now();
    for (final line in countedLines) {
      final product = await ProductRepository.getCoreById(line.productId);
      if (product == null || !product.trackStock) continue;
      final theoreticalAtCount = line.snapshotStock;
      final countedQty = line.countedQty ?? theoreticalAtCount;
      final delta = countedQty - theoreticalAtCount;
      if (delta.abs() < 0.000001) continue;

      final updatedProduct = product.copyWith(stock: product.stock + delta);
      await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
        BusinessSqliteStore.productsKey,
        updatedProduct.toJson(),
      );

      final movement = StockMovement(
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
      );
      await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
        BusinessSqliteStore.stockMovementsKey,
        movement.toJson(),
      );
    }

    final updated = session.copyWith(
      status: 'approved',
      approvedAt: now,
      approvedBy: '',
      updatedAt: now,
    );
    await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
      BusinessSqliteStore.inventoryCountsKey,
      updated.toJson(),
    );
    return updated;
  }

  static Future<InventoryCountSession?> cancelInventoryCount(
    String sessionId,
  ) async {
    final sessions = await getInventoryCounts();
    if (sessions == null) return null;
    final sessionIndex = sessions.indexWhere((item) => item.id == sessionId);
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = sessions[sessionIndex];
    if (!session.isOpen) return session;
    final updated = session.copyWith(
      status: 'cancelled',
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseService.upsertBusinessEntityJsonImmediate(
      BusinessSqliteStore.inventoryCountsKey,
      updated.toJson(),
    );
    return updated;
  }

  static Future<List<Warehouse>?> getWarehouses() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readWarehouses(db);
  }

  static Future<List<Warehouse>> listAllWarehouses() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.warehousesKey,
        (json) => Warehouse.fromJson(json),
      );

  static Future<int> countWarehouses() async {
    final db = _businessDb();
    if (db != null) {
      final rows = await getWarehouses();
      if (rows != null) return rows.length;
    }
    return _countBusinessEntityList(BusinessSqliteStore.warehousesKey);
  }

  static Future<Map<String, int>?> countMovementsAfterCount(
    String inventoryCountId,
  ) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.countInventoryMovementsAfterCount(
      db,
      inventoryCountId,
    );
  }

  static Future<List<BillOfMaterials>?> getBillOfMaterials() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readBillOfMaterials(db);
  }

  static Future<List<ManufacturingOrder>?> getManufacturingOrders() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readManufacturingOrders(db);
  }

  static Future<List<CatalogItem>?> getCatalogItems(String key) async {
    final db = _businessDb();
    if (db == null) {
      if (key != BusinessSqliteStore.categoriesKey &&
          key != BusinessSqliteStore.brandsKey &&
          key != BusinessSqliteStore.unitsKey) {
        return null;
      }
      return _readBusinessEntityList(
        key,
        (json) => CatalogItem.fromJson(json),
      );
    }
    if (!BusinessSqliteStore.isTypedEntityKey(key)) return null;
    if (key != BusinessSqliteStore.categoriesKey &&
        key != BusinessSqliteStore.brandsKey &&
        key != BusinessSqliteStore.unitsKey) {
      return null;
    }
    final table = key == BusinessSqliteStore.categoriesKey
        ? 'catalog_categories'
        : key == BusinessSqliteStore.brandsKey
            ? 'catalog_brands'
            : 'catalog_units';
    return BusinessSqliteStore.readCatalogItems(db, table);
  }

  static Future<List<SupplierProductPrice>?> getSupplierProductPrices() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSupplierProductPrices(db);
  }

  static Future<SupplierProductPrice?> getSupplierProductPriceById(
    String id,
  ) async {
    final db = _businessDb();
    if (db == null) return null;
    final rows = await BusinessSqliteStore.readSupplierProductPrices(db);
    for (final item in rows) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Future<SupplierProductPrice> addOrUpdateSupplierProductPrice(
    BusinessSessionContext context,
    SupplierProductPrice price,
  ) async {
    context.requirePermission(AppPermission.suppliersManage);
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
    final existing = await getSupplierProductPrices();
    final rows = existing ?? <SupplierProductPrice>[];
    final now = DateTime.now();
    final existingIndex = rows.indexWhere((item) => item.id == price.id);
    final duplicateIndex = rows.indexWhere(
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
        ? rows[existingIndex]
        : (duplicateIndex != -1 ? rows[duplicateIndex] : null);
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
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: previous == null ? price.version : previous.version + 1,
      lastModifiedByDeviceId: context.deviceId,
      clearDeletedAt: true,
    );
    final changedPreferredRows = <SupplierProductPrice>[];
    if (normalized.isPreferred) {
      for (var i = 0; i < rows.length; i += 1) {
        final item = rows[i];
        if (!item.isDeleted &&
            item.productId == cleanProductId &&
            item.id != normalized.id &&
            item.isPreferred) {
          final updated = item.copyWith(
            isPreferred: false,
            updatedAt: now,
            syncStatus: 'pending',
            lastModifiedByDeviceId: context.deviceId,
          );
          rows[i] = updated;
          changedPreferredRows.add(updated);
        }
      }
    }
    final isCreate = existingIndex == -1 && duplicateIndex == -1;
    if (existingIndex != -1) {
      rows[existingIndex] = normalized;
    } else if (duplicateIndex != -1) {
      normalized = normalized.copyWith(
        id: rows[duplicateIndex].id,
        createdAt: rows[duplicateIndex].createdAt,
      );
      rows[duplicateIndex] = normalized;
    }
    await _upsertEntityJson(
      BusinessSqliteStore.supplierProductPricesKey,
      normalized.toJson(),
    );
    for (final changed in changedPreferredRows) {
      await _upsertEntityJson(
        BusinessSqliteStore.supplierProductPricesKey,
        changed.toJson(),
      );
      await _recordBusinessSyncChange(
        context: context,
        entityType: 'supplier_product_price',
        entityId: changed.id,
        operation: 'update',
        payload: changed.toJson(),
      );
    }
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'supplier_product_price',
      entityId: normalized.id,
      operation: isCreate ? 'create' : 'update',
      payload: normalized.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.supplierProductPricesKey,
    );
    return normalized;
  }

  static Future<void> deleteSupplierProductPrice(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.suppliersManage);
    final current = await getSupplierProductPriceById(id);
    if (current == null) return;
    final deleted = current.copyWith(
      deletedAt: DateTime.now(),
      syncStatus: 'pending',
      lastModifiedByDeviceId: context.deviceId,
    );
    await _softDeleteEntityJson(
      BusinessSqliteStore.supplierProductPricesKey,
      deleted.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'supplier_product_price',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _refreshEntityAndSync(
      context,
      BusinessSqliteStore.supplierProductPricesKey,
    );
  }

  static Future<List<PriceList>?> getPriceLists() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readPriceLists(db);
  }

  static Future<List<ProductPrice>?> getProductPrices() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProductPrices(db);
  }

  static Future<List<ProductPriceOverride>?> getProductPriceOverrides() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProductPriceOverrides(db);
  }

  static Future<List<ProductCost>?> getProductCosts() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProductCosts(db);
  }

  static Future<List<CostingMethodHistory>?> getCostingMethodHistory() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readCostingMethodHistory(db);
  }

  static Future<List<InventoryCostLayer>?> getInventoryCostLayers() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readInventoryCostLayers(db);
  }

  static Future<double> _warehouseStockForProduct(
    String productId,
    String warehouseId,
  ) async {
    final db = _businessDb();
    if (db == null) return 0;
    final row = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS value
      FROM stock_movements
      WHERE deleted_at = '' AND product_id = ? AND warehouse_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(productId),
        Variable<String>(warehouseId),
      ],
    ).getSingle();
    return (row.data['value'] as num?)?.toDouble() ?? 0;
  }

  static Future<Warehouse> createWarehouse({
    required BusinessSessionContext context,
    required String name,
    String code = '',
    String location = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) throw ArgumentError('Warehouse name is required.');
    final existing = await getWarehouses() ?? const <Warehouse>[];
    if (existing.any(
      (item) => !item.isDeleted && item.name.toLowerCase() == cleanedName.toLowerCase(),
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
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.warehousesKey, warehouse.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'warehouse',
      entityId: warehouse.id,
      operation: 'create',
      payload: warehouse.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.warehousesKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return warehouse;
  }

  static Future<void> transferStock({
    required BusinessSessionContext context,
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be positive.');
    }
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    final product = await ProductRepository.getCoreById(productId);
    if (product == null) throw ArgumentError('Product not found.');
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final warehouses = await getWarehouses() ?? const <Warehouse>[];
    final fromWarehouse = warehouses.firstWhere(
      (item) => item.id == fromWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Source warehouse not found.'),
    );
    final toWarehouse = warehouses.firstWhere(
      (item) => item.id == toWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Destination warehouse not found.'),
    );
    final available = await _warehouseStockForProduct(productId, fromWarehouseId);
    if (available < quantity) {
      throw StateError('Not enough stock in ${fromWarehouse.name}.');
    }
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    final outMovement = StockMovement(
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
      unitCost: product.usdCost,
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      lastModifiedByDeviceId: context.deviceId,
    );
    final inMovement = outMovement.copyWith(
      type: 'warehouse_transfer_in',
      quantity: quantity,
      reason: 'Warehouse transfer from ${fromWarehouse.name}',
      warehouseId: toWarehouse.id,
      warehouseName: toWarehouse.name,
      updatedAt: now,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, outMovement.toJson());
    await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, inMovement.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'stock_movement',
      entityId: outMovement.id,
      operation: 'transfer',
      payload: outMovement.toJson(),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'stock_movement',
      entityId: inMovement.id,
      operation: 'transfer',
      payload: inMovement.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> reviewAutoCorrection(
    BusinessSessionContext context,
    String movementId, {
    String note = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    final movements = await getStockMovements() ?? const <StockMovement>[];
    final index = movements.indexWhere((item) => item.id == movementId);
    if (index == -1) throw ArgumentError('Stock movement not found.');
    final movement = movements[index];
    if (movement.type != 'auto_correction') {
      throw StateError('Only automatic corrections can be reviewed here.');
    }
    if (movement.isReviewed) return;
    final now = DateTime.now();
    final updated = movement.copyWith(
      reviewedAt: now,
      reviewedBy: context.activeUser?.fullName.trim().isNotEmpty == true
          ? context.activeUser!.fullName.trim()
          : (context.activeUser?.username ?? context.currentRole),
      reviewNote: note.trim(),
      updatedAt: now,
      syncStatus: 'pending',
      version: movement.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, updated.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'stock_movement',
      entityId: updated.id,
      operation: 'review',
      payload: updated.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> adjustStock({
    required BusinessSessionContext context,
    required String productId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    if (quantityDelta == 0) return;
    final product = await ProductRepository.getCoreById(productId);
    if (product == null) throw ArgumentError('Product not found.');
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final now = DateTime.now();
    final updatedProduct = product.copyWith(
      stock: product.stock + quantityDelta,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: product.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.productsKey, updatedProduct.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product',
      entityId: updatedProduct.id,
      operation: 'update',
      payload: updatedProduct.toJson(),
    );
    final movement = StockMovement(
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
      deviceId: context.deviceId,
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, movement.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'stock_movement',
      entityId: movement.id,
      operation: 'adjust',
      payload: movement.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
  }

  static Future<BillOfMaterials> createBillOfMaterials({
    required BusinessSessionContext context,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    if (name.trim().isEmpty) throw ArgumentError('BOM name is required.');
    if (outputQuantity <= 0) {
      throw ArgumentError('Output quantity must be greater than zero.');
    }
    if (components.isEmpty) {
      throw ArgumentError('BOM must contain at least one component.');
    }
    final output = await ProductRepository.getCoreById(outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final cleanedComponents = <BillOfMaterialsLine>[];
    for (final component in components) {
      if (component.quantity <= 0) {
        throw ArgumentError('Component quantity must be greater than zero.');
      }
      if (component.productId == outputProductId) {
        throw ArgumentError('Output product cannot be used as a component in the same BOM.');
      }
      final product = await ProductRepository.getCoreById(component.productId);
      if (product == null) {
        throw ArgumentError('Component product was not found.');
      }
      cleanedComponents.add(
        component.copyWith(
          productName: product.name,
          unitCost: product.usdCost,
        ),
      );
    }
    final now = DateTime.now();
    final bom = BillOfMaterials(
      id: '${now.microsecondsSinceEpoch}-bom',
      name: name.trim(),
      outputProductId: output.id,
      outputProductName: output.name,
      outputQuantity: outputQuantity,
      components: cleanedComponents,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.billsOfMaterialsKey, bom.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'bill_of_materials',
      entityId: bom.id,
      operation: 'create',
      payload: bom.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.billsOfMaterialsKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return bom;
  }

  static Future<ManufacturingOrder> completeManufacturingOrder({
    required BusinessSessionContext context,
    required String bomId,
    required double quantity,
    String warehouseId = '',
    String notes = '',
  }) async {
    context.requirePermission(AppPermission.productsEdit);
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final boms = await getBillOfMaterials() ?? const <BillOfMaterials>[];
    final bom = boms.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = await ProductRepository.getCoreById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final factor = quantity / bom.outputQuantity;
    final warehouses = await getWarehouses() ?? const <Warehouse>[];
    final warehouse = warehouseId.trim().isEmpty
        ? warehouses.firstWhere(
            (item) => item.id == Warehouse.defaultId && !item.isDeleted,
            orElse: () => warehouses.isNotEmpty
                ? warehouses.first
                : Warehouse(
                    id: Warehouse.defaultId,
                    name: Warehouse.defaultName,
                    isDefault: true,
                  ),
          )
        : warehouses.firstWhere(
            (item) => item.id == warehouseId && !item.isDeleted,
            orElse: () => throw ArgumentError('Warehouse not found.'),
          );
    for (final component in bom.components) {
      final product = await ProductRepository.getCoreById(component.productId);
      if (product == null || !product.trackStock) continue;
      final requiredQty = component.quantity * factor;
      if (product.stock < requiredQty) {
        throw ArgumentError(
          'Insufficient stock for ${product.name}. Required: $requiredQty, available: ${product.stock}.',
        );
      }
    }
    final now = DateTime.now();
    final order = ManufacturingOrder(
      id: '${now.microsecondsSinceEpoch}-mfg',
      orderNo: 'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
      bomId: bom.id,
      bomName: bom.name,
      outputProductId: output.id,
      outputProductName: output.name,
      quantity: quantity,
      notes: notes.trim(),
      date: now,
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    for (var lineIndex = 0; lineIndex < bom.components.length; lineIndex += 1) {
      final component = bom.components[lineIndex];
      final product = await ProductRepository.getCoreById(component.productId);
      if (product == null || !product.trackStock) continue;
      final usedQty = component.quantity * factor;
      final updated = product.copyWith(
        stock: product.stock - usedQty,
        updatedAt: now,
        deviceId: context.deviceId,
        syncStatus: 'pending',
        version: product.version + 1,
        lastModifiedByDeviceId: context.deviceId,
      );
      await _upsertEntityJson(BusinessSqliteStore.productsKey, updated.toJson());
      await _recordBusinessSyncChange(
        context: context,
        entityType: 'product',
        entityId: updated.id,
        operation: 'update',
        payload: updated.toJson(),
      );
      final movement = StockMovement(
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
        unitCost: product.usdCost,
        createdAt: now,
        updatedAt: now,
        deviceId: context.deviceId,
        storeId: context.appIdentity.storeId,
        branchId: context.appIdentity.branchId,
        lastModifiedByDeviceId: context.deviceId,
      );
      await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, movement.toJson());
      await _recordBusinessSyncChange(
        context: context,
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'manufacturing_consume',
        payload: movement.toJson(),
      );
    }

    final outputUpdated = output.copyWith(
      stock: output.stock + quantity,
      cost: bom.unitCost,
      usdCost: bom.unitCost,
      originalCost: bom.unitCost,
      costCurrency: 'USD',
      costExchangeRateAtEntry: context.storeProfile.usdToLbpRate,
      updatedAt: now,
      deviceId: context.deviceId,
      syncStatus: 'pending',
      version: output.version + 1,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.productsKey, outputUpdated.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'product',
      entityId: outputUpdated.id,
      operation: 'update',
      payload: outputUpdated.toJson(),
    );
    final outputMovement = StockMovement(
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
      unitCost: bom.unitCost,
      createdAt: now,
      updatedAt: now,
      deviceId: context.deviceId,
      storeId: context.appIdentity.storeId,
      branchId: context.appIdentity.branchId,
      lastModifiedByDeviceId: context.deviceId,
    );
    await _upsertEntityJson(BusinessSqliteStore.stockMovementsKey, outputMovement.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'stock_movement',
      entityId: outputMovement.id,
      operation: 'manufacturing_output',
      payload: outputMovement.toJson(),
    );
    await _upsertEntityJson(BusinessSqliteStore.manufacturingOrdersKey, order.toJson());
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'complete',
      payload: order.toJson(),
    );
    await _refreshMaterializedSummaries();
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.productsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.stockMovementsKey);
    await context.refreshAfterDatabaseChange(BusinessSqliteStore.manufacturingOrdersKey);
    await context.refreshAfterDatabaseChange(SyncSqliteStore.syncChangesKey);
    return order;
  }
}

class WarehouseRepository {
  WarehouseRepository._();

  static Future<List<Warehouse>> listAll() async =>
      InventoryRepository.listAllWarehouses();

  static Future<int> countAll() async =>
      InventoryRepository.countWarehouses();
}

class StockMovementRepository {
  StockMovementRepository._();

  static Future<List<StockMovement>> listAll() async =>
      InventoryRepository.listStockMovements();

  static Future<int> countAll() async =>
      InventoryRepository.countStockMovements();
}

class AccountTransactionRepository {
  AccountTransactionRepository._();

  static Future<List<AccountTransaction>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.accountTransactionsKey,
        (json) => AccountTransaction.fromJson(json),
      );

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final rows = await AccountingRepository.getAccountTransactions();
      if (rows != null) return rows.length;
    }
    return _countBusinessEntityList(BusinessSqliteStore.accountTransactionsKey);
  }
}

class RoleRepository {
  RoleRepository._();

  static Future<List<UserRole>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.rolesKey,
        (json) => UserRole.fromJson(json),
      );

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final roles = await BusinessSqliteStore.readRoles(db);
      return roles.length;
    }
    return _countBusinessEntityList(BusinessSqliteStore.rolesKey);
  }

  static Future<UserRole?> getById(String id) async {
    final roles = await listAll();
    for (final role in roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  static Future<UserRole> addOrUpdateRole(
    BusinessSessionContext context,
    UserRole role,
  ) async {
    context.requirePermission(AppPermission.rolesManage);
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
    final existing = List<UserRole>.from(await listAll());
    final index = existing.indexWhere((item) => item.id == id);
    if (index == -1) {
      existing.add(saved);
    } else {
      if (existing[index].isSystem) {
        throw StateError('System roles cannot be edited.');
      }
      existing[index] = saved;
    }
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.rolesKey,
      existing.map((item) => item.toJson()).toList(growable: false),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'role',
      entityId: saved.id,
      operation: index == -1 ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _refreshEntityAndSync(context, BusinessSqliteStore.rolesKey,
        refreshSummaries: false);
    return saved;
  }

  static Future<void> deleteRole(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.rolesManage);
    if (id == 'admin') throw StateError('The Admin role cannot be deleted.');
    final roles = List<UserRole>.from(await listAll());
    final users = List<AppUser>.from(await UserRepository.listAll());
    if (users.any((user) => user.roleId == id)) {
      throw StateError('Move users to another role before deleting this role.');
    }
    final removed = roles.firstWhere(
      (role) => role.id == id && !role.isSystem,
    );
    roles.removeWhere((role) => role.id == removed.id && !role.isSystem);
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.rolesKey,
      roles.map((item) => item.toJson()).toList(growable: false),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'role',
      entityId: id,
      operation: 'delete',
      payload: removed.toJson(),
    );
    await _refreshEntityAndSync(context, BusinessSqliteStore.rolesKey,
        refreshSummaries: false);
  }
}

class UserRepository {
  UserRepository._();

  static Future<List<AppUser>> listAll() async =>
      _readBusinessEntityList(
        BusinessSqliteStore.usersKey,
        (json) => AppUser.fromJson(json),
      );

  static Future<List<AppUser>> listActive() async {
    final users = await listAll();
    return users.where((user) => user.isActive).toList(growable: false);
  }

  static Future<int> countAll() async {
    final db = _businessDb();
    if (db != null) {
      final users = await BusinessSqliteStore.readUsers(db);
      return users.length;
    }
    return _countBusinessEntityList(BusinessSqliteStore.usersKey);
  }

  static Future<int> countActive() async {
    final users = await listAll();
    return users.where((user) => user.isActive).length;
  }

  static Future<AppUser?> getById(String id) async {
    final users = await listAll();
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  static Future<AppUser?> getByUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final users = await listAll();
    for (final user in users) {
      if (user.username.trim().toLowerCase() == normalized) return user;
    }
    return null;
  }

  static Future<AppUser> addOrUpdateUser(
    BusinessSessionContext context,
    AppUser user, {
    String? password,
  }) async {
    context.requirePermission(AppPermission.usersManage);
    if (user.fullName.trim().isEmpty || user.username.trim().isEmpty) {
      throw ArgumentError('Name and username are required.');
    }
    if (await RoleRepository.getById(user.roleId) == null) {
      throw ArgumentError('Role not found.');
    }
    final existing = List<AppUser>.from(await listAll());
    final normalizedUsername = user.username.trim().toLowerCase();
    final duplicate = existing.any(
      (item) =>
          item.id != user.id &&
          item.username.trim().toLowerCase() == normalizedUsername,
    );
    if (duplicate) throw ArgumentError('Username already exists.');
    final now = DateTime.now();
    final isCreate = user.id.trim().isEmpty ||
        existing.indexWhere((item) => item.id == user.id) == -1;
    if (isCreate && (password == null || password.trim().length < 4)) {
      throw ArgumentError('Password must be at least 4 characters.');
    }
    final id = isCreate ? 'user_${now.microsecondsSinceEpoch}' : user.id;
    final index = existing.indexWhere((item) => item.id == id);
    final current = index == -1 ? null : existing[index];
    final editingStoreOwner = current != null && current.isSystem && current.roleId == 'admin';
    if (editingStoreOwner) {
      if (password != null &&
          password.trim().isNotEmpty &&
          password.trim().length < 6) {
        throw ArgumentError(
            'Store Owner password must be at least 6 characters.');
      }
      if (user.roleId != 'admin' || user.isActive != true) {
        throw StateError(
          'Store Owner must always keep Full Access and cannot be disabled.',
        );
      }
      if (user.extraPermissions.isNotEmpty ||
          user.deniedPermissions.isNotEmpty) {
        throw StateError(
          'Store Owner permissions are locked and cannot have local overrides.',
        );
      }
    }
    final saved = AppUser(
      id: id,
      fullName: user.fullName.trim(),
      username: normalizedUsername,
      passwordHash: password != null && password.trim().isNotEmpty
          ? await PasswordHashing.hashPassword(password.trim())
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
    if (index == -1) {
      existing.add(saved);
    } else {
      if (existing[index].isSystem && saved.roleId != 'admin') {
        throw StateError('The built-in admin user must keep the Admin role.');
      }
      if (existing[index].isSystem && !editingStoreOwner) {
        throw StateError('System users cannot be edited as regular local users.');
      }
      existing[index] = saved;
    }
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.usersKey,
      existing.map((item) => item.toJson()).toList(growable: false),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'user',
      entityId: saved.id,
      operation: isCreate ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _refreshEntityAndSync(context, BusinessSqliteStore.usersKey,
        refreshSummaries: false);
    return saved;
  }

  static Future<void> deleteUser(
    BusinessSessionContext context,
    String id,
  ) async {
    context.requirePermission(AppPermission.usersManage);
    final users = await listAll();
    final user = users.firstWhere((item) => item.id == id);
    final adminCount =
        users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) {
      throw StateError('Create another active admin before deleting this user.');
    }
    if (user.isSystem) {
      throw StateError('The built-in admin user cannot be deleted.');
    }
    final remaining = users.where((item) => item.id != id).toList(growable: false);
    await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
      BusinessSqliteStore.usersKey,
      remaining.map((item) => item.toJson()).toList(growable: false),
    );
    await _recordBusinessSyncChange(
      context: context,
      entityType: 'user',
      entityId: id,
      operation: 'delete',
      payload: user.toJson(),
    );
    await _refreshEntityAndSync(context, BusinessSqliteStore.usersKey,
        refreshSummaries: false);
  }
}

class AccountingRepository {
  AccountingRepository._();

  static Future<Map<String, Object?>?> buildDashboardSummary({
    required DateTime reference,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildDashboardSummary(
      db,
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildReportsSummary({
    required DateTime reference,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildReportsSummary(
      db,
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildMetrics({
    required DateTime reference,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.buildAccountingMetrics(
      db,
      reference: reference,
    );
  }

  static Future<List<AccountTransaction>?> getAccountTransactions() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readAccountTransactions(db);
  }

  static Future<BusinessQueryPage<AccountTransaction>?> queryAccountTransactionsPage({
    String query = '',
    bool cashOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryAccountTransactions(
      db,
      query: query,
      cashOnly: cashOnly,
      limit: limit,
      offset: offset,
    );
  }
}

class BusinessSummaryRepository {
  BusinessSummaryRepository._();

  static Future<Map<String, Object?>?> buildPurchasesOverview({
    DateTime? reference,
  }) async {
    final db = _businessDb();
    if (db != null) {
      return PurchaseRepository.buildOverview(reference: reference);
    }
    final purchases = await PurchaseRepository.listAll();
    final active = purchases.where((purchase) => !purchase.isDeleted).toList();
    final ref = reference ?? DateTime.now();
    final monthStart = DateTime(ref.year, ref.month);
    final nextMonth = DateTime(ref.year, ref.month + 1);
    bool isInMonth(Purchase purchase) =>
        !purchase.date.isBefore(monthStart) && purchase.date.isBefore(nextMonth);
    return <String, Object?>{
      'totalCount': active.length,
      'totalPurchasesAmount':
          active.fold<double>(0, (sum, purchase) => sum + purchase.subtotal),
      'monthlyTotal': active
          .where(isInMonth)
          .fold<double>(0, (sum, purchase) => sum + purchase.subtotal),
      'monthlyCount': active.where(isInMonth).length,
      'draftTotal': active
          .where((purchase) => purchase.status.toLowerCase() == 'draft')
          .fold<double>(0, (sum, purchase) => sum + purchase.subtotal),
      'draftCount':
          active.where((purchase) => purchase.status.toLowerCase() == 'draft').length,
      'receivedCount':
          active.where((purchase) => purchase.status.toLowerCase() == 'received').length,
      'returnedCount':
          active.where((purchase) => purchase.status.toLowerCase() == 'returned').length,
      'cancelledCount':
          active.where((purchase) => purchase.status.toLowerCase() == 'cancelled').length,
      'pendingPurchaseCount':
          active.where((purchase) => purchase.status.toLowerCase() == 'draft').length,
    };
  }

  static Future<Map<String, Object?>?> buildExpensesOverview({
    String query = '',
    String status = 'all',
  }) async {
    final db = _businessDb();
    if (db != null) {
      return ExpenseRepository.buildOverview(query: query, status: status);
    }
    final expenses = await ExpenseRepository.listAll();
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedStatus = status.trim().toLowerCase();
    final filtered = expenses.where((expense) {
      if (expense.isDeleted) return false;
      if (normalizedStatus.isNotEmpty &&
          normalizedStatus != 'all' &&
          expense.status.toLowerCase() != normalizedStatus) {
        return false;
      }
      if (normalizedQuery.isEmpty) return true;
      return expense.searchText.contains(normalizedQuery);
    }).toList(growable: false);
    return <String, Object?>{
      'totalCount': filtered.length,
      'totalExpensesAmount':
          filtered.fold<double>(0, (sum, expense) => sum + expense.amount),
      'draftCount':
          filtered.where((expense) => expense.status.toLowerCase() == 'draft').length,
      'postedCount':
          filtered.where((expense) => expense.status.toLowerCase() == 'posted').length,
      'cancelledCount': filtered
          .where((expense) => expense.status.toLowerCase() == 'cancelled')
          .length,
      'categoryCount': filtered
          .map((expense) => expense.category.trim().toLowerCase())
          .where((category) => category.isNotEmpty)
          .toSet()
          .length,
    };
  }

  static Future<Map<String, Object?>?> buildInventoryOverview() async {
    final db = _businessDb();
    if (db == null) {
      final products = await ProductRepository.listAll();
      final active = products.where((product) => !product.isDeleted).toList();
      return <String, Object?>{
        'productCount': active.length,
        'totalUnits':
            active.fold<double>(0, (sum, product) => sum + product.stock),
        'lowStockCount':
            active.where((product) => product.isLowStock).length,
        'inventoryRetailValue': active
            .where((product) => product.trackStock)
            .fold<double>(0, (sum, product) => sum + (product.usdPrice * product.stock)),
        'pendingAutoCorrectionCount': 0,
      };
    }
    final dashboard = await BusinessSqliteStore.buildDashboardSummary(
      db,
      reference: DateTime.now(),
    );
    final inventory = await BusinessSqliteStore.buildInventoryOverview(db);
    return <String, Object?>{
      ...dashboard,
      ...inventory,
    };
  }

  static Future<double> totalSalesAmount() async {
    final db = _businessDb();
    if (db == null) {
      final sales = await SaleRepository.listAll();
      return sales
          .where((sale) => !sale.isDeleted && !sale.isCancelled)
          .fold<double>(0, (sum, sale) => sum + sale.effectiveTransactionAmount);
    }
    final row = await db.customSelect('''
      SELECT COALESCE(SUM(transaction_amount), 0) AS total
      FROM sales
      WHERE deleted_at = ''
        AND lower(status) NOT IN ('cancelled', 'returned')
    ''').getSingle();
    return (row.data['total'] as num?)?.toDouble() ?? 0;
  }

  static Future<double> estimateProfit({DateTime? reference}) async {
    final db = _businessDb();
    if (db != null) {
      final summary = await AccountingRepository.buildReportsSummary(
        reference: reference ?? DateTime.now(),
      );
      return (summary?['estimatedProfit'] as num?)?.toDouble() ?? 0;
    }
    final sales = await SaleRepository.listAll();
    final grossProfit = sales
        .where((sale) => !sale.isDeleted && !sale.isCancelled)
        .fold<double>(0, (sum, sale) => sum + sale.grossProfit);
    final totalExpenses = await totalExpensesAmount();
    return grossProfit - totalExpenses;
  }

  static Future<double> totalExpensesAmount() async {
    final db = _businessDb();
    if (db != null) {
      final overview = await buildExpensesOverview();
      return (overview?['totalExpensesAmount'] as num?)?.toDouble() ?? 0;
    }
    final expenses = await ExpenseRepository.listAll();
    return expenses
        .where((expense) =>
            !expense.isDeleted && expense.status.toLowerCase() == 'posted')
        .fold<double>(0, (sum, expense) => sum + expense.amount);
  }

  static Future<double> totalPurchasesAmount() async {
    final overview = await buildPurchasesOverview();
    return (overview?['totalPurchasesAmount'] as num?)?.toDouble() ?? 0;
  }

  static Future<int> pendingPurchaseCount() async {
    final overview = await buildPurchasesOverview();
    return (overview?['pendingPurchaseCount'] as num?)?.toInt() ?? 0;
  }

  static Future<double> inventoryRetailValue() async {
    final overview = await buildInventoryOverview();
    return (overview?['inventoryRetailValue'] as num?)?.toDouble() ?? 0;
  }

  static Future<double> inventoryCostValue() async {
    final db = _businessDb();
    if (db == null) {
      final products = await ProductRepository.listAll();
      return products
          .where((product) => !product.isDeleted && product.trackStock)
          .fold<double>(0, (sum, product) => sum + (product.usdCost * product.stock));
    }
    final row = await db.customSelect('''
      SELECT COALESCE(SUM(usd_cost * stock), 0) AS value
      FROM products
      WHERE deleted_at = '' AND track_stock = 1
    ''').getSingle();
    return (row.data['value'] as num?)?.toDouble() ?? 0;
  }

  static Future<Map<String, Object?>?> buildDataConflictSummary() async {
    int duplicateRowCount<T>(
      Iterable<T> items,
      String Function(T item) keyOf,
    ) {
      final counts = <String, int>{};
      for (final item in items) {
        final key = keyOf(item).trim().toLowerCase();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      return counts.values.fold<int>(
        0,
        (total, count) => total + (count > 1 ? count - 1 : 0),
      );
    }

    final db = _businessDb();
    if (db != null) {
      final summary = await BusinessSqliteStore.buildDashboardSummary(
        db,
        reference: DateTime.now(),
      );
      return <String, Object?>{
        'dataConflictCount':
            (summary['blockingConflictCount'] as num?)?.toInt() ?? 0,
        'blockingConflictCount':
            (summary['blockingConflictCount'] as num?)?.toInt() ?? 0,
      };
    }

    final products = await ProductRepository.listAll();
    final customers = await CustomerRepository.listAll();
    final suppliers = await SupplierRepository.listAll();
    final roles = await RoleRepository.listAll();
    final users = await UserRepository.listAll();

    final productCodeConflicts = duplicateRowCount(
      products.where((item) => !item.isDeleted),
      (item) => item.code,
    );
    final productBarcodeConflicts = duplicateRowCount(
      products.where((item) => !item.isDeleted),
      (item) => item.barcode,
    );
    final customerConflicts = duplicateRowCount(
      customers.where((item) => !item.isDeleted),
      (item) => item.name,
    );
    final supplierConflicts = duplicateRowCount(
      suppliers.where((item) => !item.isDeleted),
      (item) => item.name,
    );
    final roleConflicts = duplicateRowCount(
      roles,
      (item) => item.name,
    );
    final userConflicts = duplicateRowCount(
      users.where((item) => item.isActive),
      (item) => item.username,
    );
    final blockingConflictCount =
        productCodeConflicts +
        productBarcodeConflicts +
        customerConflicts +
        supplierConflicts +
        roleConflicts +
        userConflicts;

    return <String, Object?>{
      'dataConflictCount': blockingConflictCount,
      'blockingConflictCount': blockingConflictCount,
    };
  }
}
