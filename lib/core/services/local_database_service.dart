import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import '../../models/account_transaction.dart';
import '../../models/catalog_item.dart';
import '../../models/customer.dart';
import '../../models/delivery_note.dart';
import '../../models/expense.dart';
import '../../models/inventory_count.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/inventory_reconciliation.dart';
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
import '../../models/warehouse_inventory.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../repositories/business_repositories.dart';
import '../repositories/inventory_reconciliation_repository.dart';
import 'startup_timing_service.dart';
import '../../models/sale_summary.dart';

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
  static bool _sqliteReady = false;

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      final doubleParsed = double.tryParse(value);
      if (doubleParsed != null) return doubleParsed.toInt();
    }
    return fallback;
  }

  static double _doubleValue(Object? value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static bool get isSqliteAuthoritative =>
      _sqliteReady && SqliteMigrationManager.database != null;

  static bool get isInMemoryStoreForTesting => _memoryStoreForTesting != null;

  static bool get hasPendingBusinessEntityWrites =>
      _pendingBusinessEntityWrites.isNotEmpty;

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

  @visibleForTesting
  static Future<void> resetForTesting() async {
    _memoryStoreForTesting = null;
    _webStore = null;
    _webPreferences = null;
    _sqliteReady = false;
    _sqliteMirror.clear();
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    await SqliteMigrationManager.resetForTesting();
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
        await StartupTimingService.measure(
          'backfill_warehouse_inventory',
          () => InventoryReconciliationRepository.backfillFromLegacyData(
            activeDb,
          ),
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

  static String? getString(String key) {
    final value = _rawScalarValue(key);
    if (key == _appIdentityKey && value != null) {
      return _mergeSecureIdentitySecretsIntoIdentityJson(value);
    }
    return value;
  }

  static Future<List<StockMovement>?> getStockMovementsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getStockMovements();
  }

  static Future<List<WarehouseInventory>?> getWarehouseInventoriesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             quantity, version, created_at AS createdAt,
             updated_at AS updatedAt, device_id AS deviceId,
             sync_status AS syncStatus,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_inventory
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => WarehouseInventory.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<InventoryReconciliation>?> getInventoryReconciliationsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             legacy_product_stock AS legacyProductStock,
             ledger_balance AS ledgerBalance,
             warehouse_balance AS warehouseBalance,
             difference, classification, status, created_at AS createdAt,
             resolved_at AS resolvedAt, resolution_note AS resolutionNote
      FROM inventory_reconciliations
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => InventoryReconciliation.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>?> getStockOperationsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             operation_type AS operationType, document_type AS documentType,
             document_id AS documentId, movement_group_id AS movementGroupId,
             idempotency_key AS idempotencyKey, status, created_at AS createdAt,
             started_at AS startedAt, updated_at AS updatedAt,
             completed_at AS completedAt, failure_reason AS failureReason,
             attempt_count AS attemptCount, device_id AS deviceId,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM stock_operations
      ORDER BY store_id ASC, created_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>?> getInventoryMigrationAdjustmentsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, migration_batch_id AS migrationBatchId, store_id AS storeId,
             branch_id AS branchId, warehouse_id AS warehouseId,
             product_id AS productId, legacy_product_stock AS legacyProductStock,
             ledger_balance AS ledgerBalance, applied_delta AS appliedDelta,
             created_at AS createdAt, updated_at AS updatedAt, notes
      FROM inventory_migration_adjustments
      ORDER BY migration_batch_id ASC, store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  static Future<List<AccountTransaction>?>
      getAccountTransactionsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return AccountingRepository.getAccountTransactions();
  }

  static Future<List<Customer>?> getCustomersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return CustomerRepository.getAll();
  }

  static Future<List<Product>?> getProductsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return ProductRepository.getAll();
  }

  static Future<List<Sale>?> getSalesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getAll();
  }

  static Future<BusinessQueryPage<Sale>?> querySalesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.queryPage(
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

  static Future<BusinessQueryPage<SaleSummary>?> querySaleSummariesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.querySummaryPage(
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

  static Future<Sale?> getSaleFromSqliteById(String id) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.getById(id);
  }

  static Future<List<SaleQuotation>?> getSaleQuotationsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getQuotations();
  }

  static Future<List<DeliveryNote>?> getDeliveryNotesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getDeliveryNotes();
  }

  static Future<List<Supplier>?> getSuppliersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SupplierRepository.getAll();
  }

  static Future<List<Expense>?> getExpensesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return ExpenseRepository.getAll();
  }

  static Future<List<Warehouse>?> getWarehousesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getWarehouses();
  }

  static Future<List<Purchase>?> getPurchasesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return PurchaseRepository.getAll();
  }

  static Future<BusinessQueryPage<Purchase>?> queryPurchasesFromSqlite({
    String query = '',
    String status = 'all',
    String supplierId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.queryPage(
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

  static Future<Map<String, Object?>?> buildPurchasesOverviewFromSqlite({
    DateTime? reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.buildOverview(
      reference: reference ?? DateTime.now(),
    );
  }

  static Future<Purchase?> getPurchaseFromSqliteById(String id) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.getById(id);
  }

  static Future<List<InventoryCountSession>?>
      getInventoryCountsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getInventoryCounts();
  }

  static Future<List<BillOfMaterials>?> getBillOfMaterialsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getBillOfMaterials();
  }

  static Future<List<ManufacturingOrder>?>
      getManufacturingOrdersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getManufacturingOrders();
  }

  static Future<List<CatalogItem>?> getCatalogItemsFromSqlite(
      String key) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getCatalogItems(key);
  }

  static Future<List<SupplierProductPrice>?>
      getSupplierProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getSupplierProductPrices();
  }

  static Future<List<PriceList>?> getPriceListsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getPriceLists();
  }

  static Future<List<ProductPrice>?> getProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductPrices();
  }

  static Future<List<ProductPriceOverride>?>
      getProductPriceOverridesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductPriceOverrides();
  }

  static Future<List<ProductCost>?> getProductCostsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductCosts();
  }

  static Future<List<CostingMethodHistory>?>
      getCostingMethodHistoryFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getCostingMethodHistory();
  }

  static Future<List<InventoryCostLayer>?>
      getInventoryCostLayersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getInventoryCostLayers();
  }

  static Future<BusinessQueryPage<Customer>?> queryCustomersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
    bool includeWalkIn = false,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return CustomerRepository.queryPage(
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
    return SupplierRepository.queryPage(
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
    return ExpenseRepository.queryPage(
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
    return ExpenseRepository.sumPosted(
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
    return ProductRepository.queryPage(
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
    return ProductRepository.getCategories();
  }

  static Future<Map<String, Object?>?> buildDashboardSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildDashboardSummary(
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildReportsSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildReportsSummary(
      reference: reference,
    );
  }

  static Future<Map<String, Object?>?> buildAccountingMetricsFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildMetrics(
      reference: reference,
    );
  }

  static Future<void> upsertBusinessEntityJson(
      String key, Map<String, dynamic> payloadJson,
      {int? sortIndex}) async {
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      key,
      <Map<String, dynamic>>[Map<String, dynamic>.from(payloadJson)],
      sortIndices: <int?>[sortIndex],
    );
    _sqliteMirror.remove(key);
  }

  static Future<void> upsertSyncChange(SyncChange change) async {
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncChange(db, change);
    _sqliteMirror.remove(SyncSqliteStore.syncChangesKey);
  }

  static Future<void> upsertSyncQueueItem(SyncQueueItem item) async {
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncQueueItem(db, item);
    _sqliteMirror.remove(SyncSqliteStore.syncQueueKey);
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
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
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
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
  }

  static Future<void> runSqliteAuthoritativeTransaction(
      Future<void> Function() action) async {
    final db = SqliteMigrationManager.database;
    if (db == null || !_sqliteReady) {
      await action();
      return;
    }
    await db.transaction(() async {
      await action();
    });
  }

  static Future<void> replaceBusinessEntityJsonListImmediate(
    String key,
    List<Map<String, dynamic>> payloads,
    {List<int?>? sortIndices}
  ) async {
    var orderedPayloads = payloads;
    if (sortIndices != null && sortIndices.length == payloads.length) {
      final entries = <({Map<String, dynamic> payload, int? sortIndex})>[];
      for (var i = 0; i < payloads.length; i += 1) {
        entries.add((payload: payloads[i], sortIndex: sortIndices[i]));
      }
      entries.sort((a, b) {
        final aIndex = a.sortIndex ?? 1 << 30;
        final bIndex = b.sortIndex ?? 1 << 30;
        return aIndex.compareTo(bIndex);
      });
      orderedPayloads =
          entries.map((item) => item.payload).toList(growable: false);
    }
    final encoded = jsonEncode(orderedPayloads);
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = encoded;
      return;
    }
    if (_webStore != null) {
      _webStore![key] = encoded;
      await _persistWebString(key, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.saveKeyJson(db, key, encoded);
      _sqliteMirror[key] = encoded;
    }
  }

  static Future<void> replaceWarehouseInventoryRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM warehouse_inventory');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO warehouse_inventory
          (id, store_id, branch_id, warehouse_id, product_id, quantity,
           version, created_at, updated_at, device_id, sync_status,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ?? row['branch_id']?.toString() ?? 'main'),
          Variable<String>(row['warehouseId']?.toString() ?? row['warehouse_id']?.toString() ?? ''),
          Variable<String>(row['productId']?.toString() ?? row['product_id']?.toString() ?? ''),
          Variable<double>(_doubleValue(row['quantity'], fallback: 0)),
          Variable<int>(_intValue(row['version'], fallback: 1)),
          Variable<String>(row['createdAt']?.toString() ?? row['created_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ?? row['updated_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['deviceId']?.toString() ?? row['device_id']?.toString() ?? ''),
          Variable<String>(row['syncStatus']?.toString() ?? row['sync_status']?.toString() ?? 'synced'),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ?? row['last_modified_by_device_id']?.toString() ?? ''),
        ],
      );
    }
  }

  static Future<void> replaceStockOperationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM stock_operations');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO stock_operations
          (id, store_id, branch_id, operation_type, document_type, document_id,
           movement_group_id, idempotency_key, status, created_at, started_at,
           updated_at, completed_at, failure_reason, attempt_count, device_id,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ?? row['branch_id']?.toString() ?? 'main'),
          Variable<String>(row['operationType']?.toString() ?? row['operation_type']?.toString() ?? ''),
          Variable<String>(row['documentType']?.toString() ?? row['document_type']?.toString() ?? ''),
          Variable<String>(row['documentId']?.toString() ?? row['document_id']?.toString() ?? ''),
          Variable<String>(row['movementGroupId']?.toString() ?? row['movement_group_id']?.toString() ?? ''),
          Variable<String>(row['idempotencyKey']?.toString() ?? row['idempotency_key']?.toString() ?? ''),
          Variable<String>(row['status']?.toString() ?? 'pending'),
          Variable<String>(row['createdAt']?.toString() ?? row['created_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['startedAt']?.toString() ?? row['started_at']?.toString() ?? ''),
          Variable<String>(row['updatedAt']?.toString() ?? row['updated_at']?.toString() ?? ''),
          Variable<String>(row['completedAt']?.toString() ?? row['completed_at']?.toString() ?? ''),
          Variable<String>(row['failureReason']?.toString() ?? row['failure_reason']?.toString() ?? ''),
          Variable<int>(_intValue(row['attemptCount'] ?? row['attempt_count'], fallback: 0)),
          Variable<String>(row['deviceId']?.toString() ?? row['device_id']?.toString() ?? ''),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ?? row['last_modified_by_device_id']?.toString() ?? ''),
        ],
      );
    }
  }

  static Future<void> replaceStockMovementRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM stock_movements');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO stock_movements
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, product_id,
           product_name, movement_type, quantity, movement_date, reference_id,
           reference_no, reason, adjustment_category, notes, evidence_ref,
           warehouse_id, warehouse_name, movement_group_id, document_line_id,
           source_movement_id, reversal_of_movement_id, idempotency_key,
           unit_cost, last_modified_by_device_id, reviewed_at, reviewed_by,
           review_note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['entityType']?.toString() ?? row['entity_type']?.toString() ?? 'stock_movement'),
          Variable<String>(row['createdAt']?.toString() ?? row['created_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ?? row['updated_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['deletedAt']?.toString() ?? row['deleted_at']?.toString() ?? ''),
          Variable<String>(row['deviceId']?.toString() ?? row['device_id']?.toString() ?? ''),
          Variable<String>(row['syncStatus']?.toString() ?? row['sync_status']?.toString() ?? 'pending'),
          Variable<String>(row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ?? row['branch_id']?.toString() ?? 'main'),
          Variable<int>(_intValue(row['version'], fallback: 1)),
          Variable<int>(_intValue(row['sortIndex'] ?? row['sort_index'], fallback: 0)),
          Variable<String>(row['productId']?.toString() ?? row['product_id']?.toString() ?? ''),
          Variable<String>(row['productName']?.toString() ?? row['product_name']?.toString() ?? ''),
          Variable<String>(row['movementType']?.toString() ?? row['movement_type']?.toString() ?? row['type']?.toString() ?? 'adjustment'),
          Variable<double>(_doubleValue(row['quantity'], fallback: 0)),
          Variable<String>(row['movementDate']?.toString() ?? row['movement_date']?.toString() ?? row['date']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['referenceId']?.toString() ?? row['reference_id']?.toString() ?? ''),
          Variable<String>(row['referenceNo']?.toString() ?? row['reference_no']?.toString() ?? ''),
          Variable<String>(row['reason']?.toString() ?? ''),
          Variable<String>(row['adjustmentCategory']?.toString() ?? row['adjustment_category']?.toString() ?? ''),
          Variable<String>(row['notes']?.toString() ?? ''),
          Variable<String>(row['evidenceRef']?.toString() ?? row['evidence_ref']?.toString() ?? ''),
          Variable<String>(row['warehouseId']?.toString() ?? row['warehouse_id']?.toString() ?? 'main'),
          Variable<String>(row['warehouseName']?.toString() ?? row['warehouse_name']?.toString() ?? 'Main warehouse'),
          Variable<String>(row['movementGroupId']?.toString() ?? row['movement_group_id']?.toString() ?? ''),
          Variable<String>(row['documentLineId']?.toString() ?? row['document_line_id']?.toString() ?? ''),
          Variable<String>(row['sourceMovementId']?.toString() ?? row['source_movement_id']?.toString() ?? ''),
          Variable<String>(row['reversalOfMovementId']?.toString() ?? row['reversal_of_movement_id']?.toString() ?? ''),
          Variable<String>(row['idempotencyKey']?.toString() ?? row['idempotency_key']?.toString() ?? ''),
          Variable<double>(_doubleValue(row['unitCost'] ?? row['unit_cost'], fallback: 0)),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ?? row['last_modified_by_device_id']?.toString() ?? row['device_id']?.toString() ?? ''),
          Variable<String>(row['reviewedAt']?.toString() ?? row['reviewed_at']?.toString() ?? ''),
          Variable<String>(row['reviewedBy']?.toString() ?? row['reviewed_by']?.toString() ?? ''),
          Variable<String>(row['reviewNote']?.toString() ?? row['review_note']?.toString() ?? ''),
        ],
      );
    }
  }

  static Future<void> replaceInventoryReconciliationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM inventory_reconciliations');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO inventory_reconciliations
          (id, store_id, branch_id, warehouse_id, product_id,
           legacy_product_stock, ledger_balance, warehouse_balance, difference,
           classification, status, created_at, resolved_at, resolution_note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ?? row['branch_id']?.toString() ?? 'main'),
          Variable<String>(row['warehouseId']?.toString() ?? row['warehouse_id']?.toString() ?? ''),
          Variable<String>(row['productId']?.toString() ?? row['product_id']?.toString() ?? ''),
          Variable<double>(_doubleValue(row['legacyProductStock'] ?? row['legacy_product_stock'], fallback: 0)),
          Variable<double>(_doubleValue(row['ledgerBalance'] ?? row['ledger_balance'], fallback: 0)),
          Variable<double>(_doubleValue(row['warehouseBalance'] ?? row['warehouse_balance'], fallback: 0)),
          Variable<double>(_doubleValue(row['difference'], fallback: 0)),
          Variable<String>(row['classification']?.toString() ?? ''),
          Variable<String>(row['status']?.toString() ?? 'open'),
          Variable<String>(row['createdAt']?.toString() ?? row['created_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['resolvedAt']?.toString() ?? row['resolved_at']?.toString() ?? ''),
          Variable<String>(row['resolutionNote']?.toString() ?? row['resolution_note']?.toString() ?? ''),
        ],
      );
    }
  }

  static Future<void> replaceInventoryMigrationAdjustmentsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM inventory_migration_adjustments');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO inventory_migration_adjustments
          (id, migration_batch_id, store_id, branch_id, warehouse_id, product_id,
           legacy_product_stock, ledger_balance, applied_delta, created_at,
           updated_at, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['migrationBatchId']?.toString() ?? row['migration_batch_id']?.toString() ?? ''),
          Variable<String>(row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ?? row['branch_id']?.toString() ?? 'main'),
          Variable<String>(row['warehouseId']?.toString() ?? row['warehouse_id']?.toString() ?? ''),
          Variable<String>(row['productId']?.toString() ?? row['product_id']?.toString() ?? ''),
          Variable<double>(_doubleValue(row['legacyProductStock'] ?? row['legacy_product_stock'], fallback: 0)),
          Variable<double>(_doubleValue(row['ledgerBalance'] ?? row['ledger_balance'], fallback: 0)),
          Variable<double>(_doubleValue(row['appliedDelta'] ?? row['applied_delta'], fallback: 0)),
          Variable<String>(row['createdAt']?.toString() ?? row['created_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ?? row['updated_at']?.toString() ?? DateTime.now().toIso8601String()),
          Variable<String>(row['notes']?.toString() ?? ''),
        ],
      );
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
      final warehouseInventory = await getWarehouseInventoriesFromSqlite();
      if (warehouseInventory != null) {
        entries['warehouse_inventory'] =
            jsonEncode(warehouseInventory.map((item) => item.toJson()).toList(growable: false));
      }
      final stockOperations = await getStockOperationsFromSqlite();
      if (stockOperations != null) {
        entries['stock_operations'] = jsonEncode(stockOperations);
      }
      final inventoryReconciliations = await getInventoryReconciliationsFromSqlite();
      if (inventoryReconciliations != null) {
        entries['inventory_reconciliations'] = jsonEncode(
          inventoryReconciliations.map((item) => item.toJson()).toList(growable: false),
        );
      }
      final inventoryMigrationAdjustments =
          await getInventoryMigrationAdjustmentsFromSqlite();
      if (inventoryMigrationAdjustments != null) {
        entries['inventory_migration_adjustments'] =
            jsonEncode(inventoryMigrationAdjustments);
      }
      for (final key in SyncSqliteStore.sqliteBackedKeys) {
        final value = await SyncSqliteStore.readKeyJson(db, key);
        if (value != null) entries[key] = value;
      }
      return entries;
    }
    return const <String, String>{};
  }

  static VentioDriftDatabase? _syncDatabase() {
    if (_memoryStoreForTesting != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SqliteMigrationManager.database;
  }

  static List<SyncChange> _memorySyncChanges() {
    final raw = _memoryStore?[SyncSqliteStore.syncChangesKey];
    if (raw == null || raw.trim().isEmpty) return const <SyncChange>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SyncChange>[];
      return decoded
          .whereType<Map>()
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <SyncChange>[];
    }
  }

  static List<SyncQueueItem> _memorySyncQueue() {
    final raw = _memoryStore?[SyncSqliteStore.syncQueueKey];
    if (raw == null || raw.trim().isEmpty) return const <SyncQueueItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SyncQueueItem>[];
      return decoded
          .whereType<Map>()
          .map(
              (item) => SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <SyncQueueItem>[];
    }
  }

  static Future<int> pendingSyncQueueCountForTarget(
    String target, {
    bool readyOnly = true,
  }) async {
    final memory = _memoryStore;
    if (memory != null) {
      final queue = _memorySyncQueue();
      final now = DateTime.now();
      final staleCutoff = now.subtract(const Duration(seconds: 45));
      return queue.where((item) {
        if (item.target != target) return false;
        final isActive = item.status == 'pending' ||
            item.status == 'failed' ||
            (item.status == 'inProgress' &&
                item.updatedAt.isBefore(staleCutoff));
        if (!isActive) return false;
        if (!readyOnly) return true;
        return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
      }).length;
    }
    if (_webStore != null) {
      final queueRaw = _webStore![SyncSqliteStore.syncQueueKey] ?? '[]';
      try {
        final decoded = jsonDecode(queueRaw);
        if (decoded is! List) return 0;
        final queue = decoded
            .whereType<Map>()
            .map((item) =>
                SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        final now = DateTime.now();
        final staleCutoff = now.subtract(const Duration(seconds: 45));
        return queue.where((item) {
          if (item.target != target) return false;
          final isActive = item.status == 'pending' ||
              item.status == 'failed' ||
              (item.status == 'inProgress' &&
                  item.updatedAt.isBefore(staleCutoff));
          if (!isActive) return false;
          if (!readyOnly) return true;
          return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
        }).length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
    final now = DateTime.now();
    final staleCutoff =
        now.subtract(const Duration(seconds: 45)).toIso8601String();
    final conditions = <String>[
      'target = ?',
      "(status IN ('pending', 'failed') OR (status = 'inProgress' AND updated_at < ?))",
    ];
    final variables = <Variable<Object>>[
      Variable<String>(target),
      Variable<String>(staleCutoff),
    ];
    if (readyOnly) {
      conditions.add("(next_retry_at = '' OR next_retry_at <= ?)");
      variables.add(Variable<String>(now.toIso8601String()));
    }
    final row = await db.customSelect(
      '''
      SELECT COUNT(*) AS value
      FROM sync_queue
      WHERE ${conditions.join(' AND ')}
      ''',
      variables: variables,
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  static Future<int> pendingSyncChangesCount() async {
    final memory = _memoryStore;
    if (memory != null) {
      return _memorySyncChanges().where((item) => !item.isSynced).length;
    }
    if (_webStore != null) {
      final raw = _webStore![SyncSqliteStore.syncChangesKey] ?? '[]';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return 0;
        return decoded
            .whereType<Map>()
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => !item.isSynced)
            .length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
    final row = await db
        .customSelect(
          "SELECT COUNT(*) AS value FROM sync_events WHERE is_synced = 0",
        )
        .getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
  }

  static Future<int> outstandingSyncQueueCountForTarget(String target) async {
    final memory = _memoryStore;
    if (memory != null) {
      return _memorySyncQueue()
          .where((item) => item.target == target && item.status != 'synced')
          .length;
    }
    if (_webStore != null) {
      final queueRaw = _webStore![SyncSqliteStore.syncQueueKey] ?? '[]';
      try {
        final decoded = jsonDecode(queueRaw);
        if (decoded is! List) return 0;
        return decoded
            .whereType<Map>()
            .map((item) =>
                SyncQueueItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.target == target && item.status != 'synced')
            .length;
      } catch (_) {
        return 0;
      }
    }
    final db = _syncDatabase();
    if (db == null) return 0;
    final row = await db.customSelect(
      "SELECT COUNT(*) AS value FROM sync_queue WHERE target = ? AND status != 'synced'",
      variables: <Variable<Object>>[Variable<String>(target)],
    ).getSingle();
    return (row.data['value'] as num?)?.toInt() ?? 0;
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
  });

  final Map<String, dynamic> payload;
}
