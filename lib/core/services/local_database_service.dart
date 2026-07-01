import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import '../../models/account_transaction.dart';
import '../../models/catalog_item.dart';
import '../../models/customer.dart';
import '../../models/delivery_note.dart';
import '../../models/expense.dart';
import '../../models/inventory_count.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/manufacturing.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/product_pricing.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/sale_quotation.dart';
import '../../models/stock_movement.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/warehouse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'startup_timing_service.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _appIdentityKey = 'app_identity_v1';
  static const String _legacySecureDeviceTokenKey =
      'app_identity_device_token_v1';
  static const String _secureRecoveryKeyKey = 'app_identity_recovery_key_v1';
  static final Map<String, String> _secureStringMirror = <String, String>{};
  static Map<String, String>? _memoryStoreForTesting;
  static Map<String, String>? _webStore;
  static SharedPreferences? _webPreferences;
  static final Map<String, String> _sqliteMirror = <String, String>{};
  static final Map<String, String> _pendingScalarWrites = <String, String>{};
  static final Set<String> _pendingScalarDeletes = <String>{};
  static final Map<String, List<_PendingBusinessEntityWrite>>
      _pendingBusinessEntityWrites =
      <String, List<_PendingBusinessEntityWrite>>{};
  static final List<SyncChange> _pendingSyncChanges = <SyncChange>[];
  static final List<SyncQueueItem> _pendingSyncQueueItems = <SyncQueueItem>[];
  static Timer? _flushTimer;
  static Future<void>? _flushInProgress;
  static const Duration _flushDelay = Duration(milliseconds: 120);
  static bool _sqliteReady = false;

  static bool get isSqliteAuthoritative =>
      _sqliteReady && SqliteMigrationManager.database != null;

  static bool get canQueryBusinessSqlite =>
      _memoryStore == null && _webStore == null && isSqliteAuthoritative;

  @visibleForTesting
  static void useInMemoryStoreForTesting([Map<String, String>? seed]) {
    _memoryStoreForTesting =
        Map<String, String>.from(seed ?? const <String, String>{});
  }

  @visibleForTesting
  static void clearInMemoryStoreForTesting() {
    _memoryStoreForTesting = null;
  }

  static Future<void> initialize() async {
    if (_memoryStoreForTesting != null) return;
    if (_sqliteReady && SqliteMigrationManager.database != null) return;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _webPreferences = prefs;
      _webStore = <String, String>{
        for (final key in prefs.getKeys())
          if (prefs.getString(key) != null) key: prefs.getString(key)!,
      };
      return;
    }

    await StartupTimingService.measure(
      'local_database.sqlite_bootstrap',
      () async {
        final existingSqliteStatus = await StartupTimingService.measure(
          'sqlite_restore_or_validate',
          SqliteMigrationManager.initializeFromExistingSqliteIfValidated,
          category: 'database',
        );
        var db = SqliteMigrationManager.database;
        if (!existingSqliteStatus.sqliteFoundationReady || db == null) {
          await StartupTimingService.measure(
            'sqlite_fresh_initialize',
            SqliteMigrationManager.initializeFreshSqlite,
            category: 'database',
          );
          db = SqliteMigrationManager.database;
        }
        if (db == null) {
          throw StateError('SQLite database failed to initialize.');
        }
        final activeDb = db;

        _sqliteMirror
          ..clear()
          ..addAll(await StartupTimingService.measure(
            'hydrate_business_scalar_mirror',
            () => BusinessSqliteStore.hydrateScalarKeyMirror(activeDb),
            category: 'database',
          ))
          ..addAll(await StartupTimingService.measure(
            'hydrate_sync_scalar_mirror',
            () => SyncSqliteStore.hydrateScalarKeyMirror(activeDb),
            category: 'database',
          ));
        _pendingScalarWrites.clear();
        _pendingScalarDeletes.clear();
        _pendingBusinessEntityWrites.clear();
        _pendingSyncChanges.clear();
        _pendingSyncQueueItems.clear();
        _flushTimer?.cancel();
        _flushTimer = null;
        _flushInProgress = null;
        await StartupTimingService.measure(
          'migrate_complex_business_tables',
          () => BusinessSqliteStore.migrateComplexTablesFromPayloadJson(
            activeDb,
          ),
          category: 'database',
        );
        await StartupTimingService.measure(
          'rebuild_business_tables_without_payload_json',
          () => activeDb.rebuildBusinessTablesWithoutPayloadJson(),
          category: 'database',
        );
        _sqliteReady = true;
        await StartupTimingService.measure(
          'hydrate_secure_scalars',
          _hydrateAndMigrateSecureScalars,
          category: 'database',
        );
      },
      category: 'bootstrap',
    );
  }

  static Map<String, String>? get _memoryStore => _memoryStoreForTesting;

  static Future<void> _persistWebString(String key, String value) async {
    final prefs = _webPreferences;
    if (prefs != null) await prefs.setString(key, value);
  }

  static Future<void> _deleteWebString(String key) async {
    final prefs = _webPreferences;
    if (prefs != null) await prefs.remove(key);
  }

  static Future<void> _hydrateAndMigrateSecureScalars() async {
    // Phase 1 security split:
    // - recoveryKey stays in FlutterSecureStorage.
    // - deviceToken is application identity data and is stored back inside
    //   app_identity_v1 in the local database. Keep this legacy secure key only
    //   long enough to migrate devices that used the previous secure-token build.
    final legacySecureDeviceToken =
        (await _secureStorage.read(key: _legacySecureDeviceTokenKey))?.trim() ??
            '';
    final secureRecoveryKey =
        await _secureStorage.read(key: _secureRecoveryKeyKey);
    if (secureRecoveryKey != null) {
      _secureStringMirror[_secureRecoveryKeyKey] = secureRecoveryKey;
    }

    await _deleteRawScalarValueImmediate('cloud_api_token');

    final rawIdentity = _rawScalarValue(_appIdentityKey);
    if (rawIdentity != null && rawIdentity.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonMap(rawIdentity);
      if (decoded != null) {
        final legacyDeviceToken =
            (decoded['deviceToken'] ?? decoded['device_token'] ?? '')
                .toString()
                .trim();
        if (legacyDeviceToken.isEmpty && legacySecureDeviceToken.isNotEmpty) {
          decoded['deviceToken'] = legacySecureDeviceToken;
        }
        final legacyRecoveryKey =
            (decoded['recoveryKey'] ?? decoded['recovery_key'] ?? '')
                .toString()
                .trim();
        if (legacyRecoveryKey.isNotEmpty &&
            (_secureStringMirror[_secureRecoveryKeyKey] ?? '').isEmpty) {
          final cleanRecoveryKey = legacyRecoveryKey.toUpperCase();
          await _secureStorage.write(
              key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
          _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
        }
        final sanitized = _sanitizeAppIdentityJson(jsonEncode(decoded));
        if (sanitized != rawIdentity) {
          await _writeRawScalarValueImmediate(_appIdentityKey, sanitized);
        }
      }
    }
    if (legacySecureDeviceToken.isNotEmpty) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
    }
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String _sanitizeAppIdentityJson(String value) {
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    decoded.remove('recoveryKey');
    decoded.remove('recovery_key');
    return jsonEncode(decoded);
  }

  static String _mergeSecureIdentitySecretsIntoIdentityJson(String value) {
    final recoveryKey =
        (_secureStringMirror[_secureRecoveryKeyKey] ?? '').trim();
    if (recoveryKey.isEmpty) return value;
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    if (recoveryKey.isNotEmpty) decoded['recoveryKey'] = recoveryKey;
    return jsonEncode(decoded);
  }

  static String? _rawScalarValue(String key) {
    if (_pendingScalarDeletes.contains(key)) return null;
    final pending = _pendingScalarWrites[key];
    if (pending != null) return pending;
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
    return _sqliteMirror[key];
  }

  static Future<void> _writeRawScalarValueImmediate(
      String key, String value) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    if (_webStore != null) {
      _webStore![key] = value;
      await _persistWebString(key, value);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(db, key, value);
        } else {
          await BusinessSqliteStore.saveKeyJson(db, key, value);
        }
        _sqliteMirror[key] = value;
        return;
      }
    }
    throw StateError('SQLite database has not been initialized.');
  }

  static Future<void> _deleteRawScalarValueImmediate(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_webStore != null) {
      _webStore!.remove(key);
      await _deleteWebString(key);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(
              db, key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
  }

  static void _scheduleFlush() {
    if (_memoryStore != null || _webStore != null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () {
      unawaited(flushPendingWrites());
    });
  }

  static String? getString(String key) {
    final value = _rawScalarValue(key);
    if (key == _appIdentityKey && value != null) {
      return _mergeSecureIdentitySecretsIntoIdentityJson(value);
    }
    return value;
  }

  static Future<String?> getBusinessEntityListJson(String key) async {
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
    if (_sqliteReady) {
      final cached = _sqliteMirror[key];
      if (cached != null) return cached;
      final db = SqliteMigrationManager.database;
      if (db == null) return null;
      String? value;
      if (BusinessSqliteStore.isTypedEntityKey(key)) {
        value = await BusinessSqliteStore.readEntityListJsonByKey(db, key);
      } else if (SyncSqliteStore.isSqliteBackedKey(key)) {
        value = await SyncSqliteStore.readKeyJson(db, key);
      }
      if (value != null) _sqliteMirror[key] = value;
      return value;
    }
    return null;
  }

  static Future<List<String>> getBusinessEntityListJsonBatches(
    String key, {
    int batchSize = 100,
  }) async {
    final memory = _memoryStore;
    if (memory != null) {
      final value = memory[key];
      return value == null ? const <String>[] : <String>[value];
    }
    if (_webStore != null) {
      final value = _webStore![key];
      return value == null ? const <String>[] : <String>[value];
    }
    if (_sqliteReady) {
      final cached = _sqliteMirror[key];
      if (cached != null) return <String>[cached];
      final db = SqliteMigrationManager.database;
      if (db == null) return const <String>[];
      if (BusinessSqliteStore.isTypedEntityKey(key)) {
        return BusinessSqliteStore.readEntityListJsonBatches(
          db,
          key,
          batchSize: batchSize,
        );
      }
      if (key == SyncSqliteStore.syncChangesKey) {
        return SyncSqliteStore.readSyncChangesJsonBatches(
          db,
          batchSize: batchSize,
        );
      }
      if (key == SyncSqliteStore.syncQueueKey) {
        return SyncSqliteStore.readSyncQueueJsonBatches(
          db,
          batchSize: batchSize,
        );
      }
    }
    return const <String>[];
  }

  static Future<List<StockMovement>?> getStockMovementsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readStockMovements(db);
  }

  static Future<List<AccountTransaction>?>
      getAccountTransactionsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readAccountTransactions(db);
  }

  static Future<List<Customer>?> getCustomersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readCustomers(db);
  }

  static Future<List<Product>?> getProductsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readProducts(db);
  }

  static Future<List<Sale>?> getSalesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readSales(db);
  }

  static Future<List<SaleQuotation>?> getSaleQuotationsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readSaleQuotations(db);
  }

  static Future<List<DeliveryNote>?> getDeliveryNotesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readDeliveryNotes(db);
  }

  static Future<List<Supplier>?> getSuppliersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readSuppliers(db);
  }

  static Future<List<Expense>?> getExpensesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readExpenses(db);
  }

  static Future<List<Warehouse>?> getWarehousesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readWarehouses(db);
  }

  static Future<List<Purchase>?> getPurchasesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readPurchases(db);
  }

  static Future<List<InventoryCountSession>?>
      getInventoryCountsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readInventoryCounts(db);
  }

  static Future<List<BillOfMaterials>?> getBillOfMaterialsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readBillOfMaterials(db);
  }

  static Future<List<ManufacturingOrder>?>
      getManufacturingOrdersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readManufacturingOrders(db);
  }

  static Future<List<CatalogItem>?> getCatalogItemsFromSqlite(
      String key) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    if (!BusinessSqliteStore.isTypedEntityKey(key)) return null;
    if (key != BusinessSqliteStore.categoriesKey &&
        key != BusinessSqliteStore.brandsKey &&
        key != BusinessSqliteStore.unitsKey) {
      return null;
    }
    final table = BusinessSqliteStore.adminEntityKeys.contains(key)
        ? (key == BusinessSqliteStore.categoriesKey
            ? 'catalog_categories'
            : key == BusinessSqliteStore.brandsKey
                ? 'catalog_brands'
                : 'catalog_units')
        : null;
    if (table == null) return null;
    return BusinessSqliteStore.readCatalogItems(db, table);
  }

  static Future<List<SupplierProductPrice>?>
      getSupplierProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readSupplierProductPrices(db);
  }

  static Future<List<PriceList>?> getPriceListsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readPriceLists(db);
  }

  static Future<List<ProductPrice>?> getProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readProductPrices(db);
  }

  static Future<List<ProductPriceOverride>?>
      getProductPriceOverridesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readProductPriceOverrides(db);
  }

  static Future<List<ProductCost>?> getProductCostsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readProductCosts(db);
  }

  static Future<List<CostingMethodHistory>?>
      getCostingMethodHistoryFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readCostingMethodHistory(db);
  }

  static Future<List<InventoryCostLayer>?>
      getInventoryCostLayersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.readInventoryCostLayers(db);
  }

  static Future<BusinessQueryPage<Customer>?> queryCustomersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
    bool includeWalkIn = false,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.queryCustomers(
      db,
      query: query,
      limit: limit,
      offset: offset,
      includeWalkIn: includeWalkIn,
    );
  }

  static Future<BusinessQueryPage<Supplier>?> querySuppliersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.querySuppliers(
      db,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  static Future<BusinessQueryPage<Expense>?> queryExpensesFromSqlite({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.queryExpenses(
      db,
      query: query,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  static Future<double?> sumPostedExpensesFromSqlite({
    String query = '',
    String status = 'all',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.sumPostedExpenses(
      db,
      query: query,
      status: status,
    );
  }

  static Future<BusinessQueryPage<Product>?> queryProductsFromSqlite({
    String query = '',
    String category = '',
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
    bool stockTrackedOnly = false,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
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

  static Future<List<String>?> queryProductCategoriesFromSqlite() async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.queryProductCategories(db);
  }

  static Future<Map<String, Object?>?> buildDashboardSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.buildDashboardSummary(
      db,
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildReportsSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.buildReportsSummary(
      db,
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildAccountingMetricsFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    return BusinessSqliteStore.buildAccountingMetrics(
      db,
      reference: reference,
    );
  }

  static Future<void> upsertBusinessEntityJson(
      String key, Map<String, dynamic> payloadJson,
      {int? sortIndex}) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    final pending = _pendingBusinessEntityWrites.putIfAbsent(
      key,
      () => <_PendingBusinessEntityWrite>[],
    );
    pending.add(
      _PendingBusinessEntityWrite(
        payload: Map<String, dynamic>.from(payloadJson),
        sortIndex: sortIndex,
      ),
    );
    _sqliteMirror.remove(key);
    _scheduleFlush();
  }

  static Future<void> upsertSyncChange(SyncChange change) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    _pendingSyncChanges.add(change);
    _sqliteMirror.remove(SyncSqliteStore.syncChangesKey);
    _scheduleFlush();
  }

  static Future<void> upsertSyncQueueItem(SyncQueueItem item) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    _pendingSyncQueueItems.add(item);
    _sqliteMirror.remove(SyncSqliteStore.syncQueueKey);
    _scheduleFlush();
  }

  static Future<void> setString(String key, String value) async {
    if (key == _appIdentityKey) {
      if (_memoryStore != null || _webStore != null) {
        await _writeRawScalarValueImmediate(key, value);
        return;
      }
      final decoded = _tryDecodeJsonMap(value);
      final recoveryKey =
          (decoded?['recoveryKey'] ?? decoded?['recovery_key'] ?? '')
              .toString()
              .trim();
      if (recoveryKey.isNotEmpty) {
        final cleanRecoveryKey = recoveryKey.toUpperCase();
        await _secureStorage.write(
            key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
        _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
      }
      await _writeRawScalarValueImmediate(key, _sanitizeAppIdentityJson(value));
      return;
    }
    final memory = _memoryStore;
    if (memory != null) {
      await _writeRawScalarValueImmediate(key, value);
      return;
    }
    if (_webStore != null) {
      await _writeRawScalarValueImmediate(key, value);
      return;
    }
    if (_sqliteReady) {
      _pendingScalarDeletes.remove(key);
      _pendingScalarWrites[key] = value;
      _sqliteMirror[key] = value;
      _scheduleFlush();
      return;
    }
    await _writeRawScalarValueImmediate(key, value);
  }

  static bool containsKey(String key) {
    if (_pendingScalarDeletes.contains(key)) return false;
    if (_pendingScalarWrites.containsKey(key)) return true;
    final memory = _memoryStore;
    if (memory != null) return memory.containsKey(key);
    if (_webStore != null) return _webStore!.containsKey(key);
    if (_sqliteReady) {
      return _sqliteMirror.containsKey(key);
    }
    return false;
  }

  static Future<void> deleteString(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_webStore != null) {
      _webStore!.remove(key);
      await _deleteWebString(key);
      return;
    }

    if (key == _appIdentityKey) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      await _secureStorage.delete(key: _secureRecoveryKeyKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_secureRecoveryKeyKey);
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await setString(
              key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          _pendingScalarWrites.remove(key);
          _pendingScalarDeletes.add(key);
          _sqliteMirror.remove(key);
          _scheduleFlush();
        }
        return;
      }
    }
    return;
  }

  static Future<void> clearAll() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    final memory = _memoryStore;
    if (memory != null) {
      memory.clear();
      return;
    }
    if (_webStore != null) {
      final prefs = _webPreferences;
      final keys = List<String>.from(_webStore!.keys);
      _webStore!.clear();
      if (prefs != null) {
        for (final key in keys) {
          await prefs.remove(key);
        }
      }
      return;
    }
    await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
    await _secureStorage.delete(key: _secureRecoveryKeyKey);
    _secureStringMirror.remove(_legacySecureDeviceTokenKey);
    _secureStringMirror.remove(_secureRecoveryKeyKey);
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.clear(db);
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncChangesKey, '[]');
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncQueueKey, '[]');
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncSequenceKey, '0');
      await db.customUpdate('DELETE FROM app_logs');
      await db.customUpdate('DELETE FROM audit_logs');
      _sqliteMirror
        ..clear()
        ..addAll(<String, String>{
          SyncSqliteStore.syncChangesKey: '[]',
          SyncSqliteStore.syncQueueKey: '[]',
          SyncSqliteStore.syncSequenceKey: '0',
        });
      return;
    }
    return;
  }

  static Future<void> flushPendingWrites() async {
    if (_memoryStore != null || _webStore != null) return;
    if (_flushInProgress != null) return _flushInProgress!;

    final completer = Completer<void>();
    _flushInProgress = completer.future;
    _flushTimer?.cancel();
    _flushTimer = null;

    try {
      final db = SqliteMigrationManager.database;
      if (!_sqliteReady || db == null) return;

      final scalarDeletes = List<String>.from(_pendingScalarDeletes);
      final scalarWrites = Map<String, String>.from(_pendingScalarWrites);
      final businessWrites =
          Map<String, List<_PendingBusinessEntityWrite>>.from(
        _pendingBusinessEntityWrites,
      );
      final syncChanges = List<SyncChange>.from(_pendingSyncChanges);
      final syncQueueItems = List<SyncQueueItem>.from(_pendingSyncQueueItems);

      _pendingScalarDeletes.clear();
      _pendingScalarWrites.clear();
      _pendingBusinessEntityWrites.clear();
      _pendingSyncChanges.clear();
      _pendingSyncQueueItems.clear();

      for (final key in scalarDeletes) {
        await _deleteRawScalarValueImmediate(key);
      }
      for (final entry in scalarWrites.entries) {
        await _writeRawScalarValueImmediate(entry.key, entry.value);
      }
      for (final entry in businessWrites.entries) {
        _sqliteMirror.remove(entry.key);
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          entry.key,
          entry.value.map((item) => item.payload).toList(growable: false),
          sortIndices:
              entry.value.map((item) => item.sortIndex).toList(growable: false),
        );
      }
      if (syncChanges.isNotEmpty) {
        await SyncSqliteStore.upsertSyncChanges(db, syncChanges);
      }
      if (syncQueueItems.isNotEmpty) {
        await SyncSqliteStore.upsertSyncQueueItems(db, syncQueueItems);
      }
    } finally {
      _flushInProgress = null;
      completer.complete();
      if (_pendingScalarDeletes.isNotEmpty ||
          _pendingScalarWrites.isNotEmpty ||
          _pendingBusinessEntityWrites.isNotEmpty ||
          _pendingSyncChanges.isNotEmpty ||
          _pendingSyncQueueItems.isNotEmpty) {
        _scheduleFlush();
      }
    }
  }

  static List<String> keys() {
    final memory = _memoryStore;
    if (memory != null) return memory.keys.toList()..sort();
    if (_webStore != null) return _webStore!.keys.toList()..sort();
    if (_sqliteReady) return _sqliteMirror.keys.toList()..sort();
    return const <String>[];
  }

  static Map<String, String> allEntries() {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_webStore != null) return Map<String, String>.from(_webStore!);
    if (_sqliteReady) return Map<String, String>.from(_sqliteMirror);
    return const <String, String>{};
  }

  /// Full diagnostic/admin snapshot for the Database page.
  ///
  /// `allEntries()` intentionally stays startup-fast after SQLite became
  /// authoritative and only returns the scalar mirror. The Database page,
  /// however, is an explicit admin browser and must show the real typed SQLite
  /// tables as well. This method hydrates those tables on demand.
  static Future<Map<String, String>> adminEntries() async {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_webStore != null) return Map<String, String>.from(_webStore!);
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db == null) return Map<String, String>.from(_sqliteMirror);
      final entries = Map<String, String>.from(_sqliteMirror);
      for (final key in BusinessSqliteStore.adminEntityKeys) {
        final value =
            await BusinessSqliteStore.readEntityListJsonByKey(db, key);
        if (value != null) entries[key] = value;
      }
      for (final key in SyncSqliteStore.sqliteBackedKeys) {
        final value = await SyncSqliteStore.readKeyJson(db, key);
        if (value != null) entries[key] = value;
      }
      return entries;
    }
    return const <String, String>{};
  }

  static bool get isEmpty {
    final memory = _memoryStore;
    if (memory != null) return memory.isEmpty;
    if (_sqliteReady) return _sqliteMirror.isEmpty;
    return true;
  }
}

class _PendingBusinessEntityWrite {
  const _PendingBusinessEntityWrite({
    required this.payload,
    this.sortIndex,
  });

  final Map<String, dynamic> payload;
  final int? sortIndex;
}
