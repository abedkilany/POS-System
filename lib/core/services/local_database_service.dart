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
import 'web_indexed_store.dart';
import '../../models/sale_summary.dart';

part 'local_database_service_impl_01.dart';
part 'local_database_service_impl_02.dart';
part 'local_database_service_impl_03.dart';
part 'local_database_service_impl_04.dart';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

const String _webWarehouseInventoryKey = 'web_warehouse_inventory_v1';

const String _webStockOperationsKey = 'web_stock_operations_v1';

const String _webInventoryReconciliationsKey =
    'web_inventory_reconciliations_v1';

const String _webInventoryMigrationAdjustmentsKey =
    'web_inventory_migration_adjustments_v1';

const String _appIdentityKey = 'app_identity_v1';

const String _legacySecureDeviceTokenKey = 'app_identity_device_token_v1';

const String _secureRecoveryKeyKey = 'app_identity_recovery_key_v1';

const Set<String> _phase4SecureKeys = <String>{
  _secureRecoveryKeyKey,
  'account_auth_admin_token_v1',
  'account_auth_account_token_v1',
  'account_auth_refresh_token_v1',
  'google_drive_backup_client_secret_v1',
  'google_drive_backup_refresh_token_v1',
  'google_drive_backup_access_token_v1',
};

final Map<String, String> _secureStringMirror = <String, String>{};

Map<String, String>? _memoryStoreForTesting;

Map<String, String>? _webStore;

SharedPreferences? _webPreferences;

WebIndexedStore? _webIndexedStore;

Future<void> _webIndexedWriteChain = Future<void>.value();

final Map<String, String> _sqliteMirror = <String, String>{};

Future<void>? _initializeInFlight;

final Map<String, String> _pendingScalarWrites = <String, String>{};

final Set<String> _pendingScalarDeletes = <String>{};

final Map<String, List<_PendingBusinessEntityWrite>>
    _pendingBusinessEntityWrites =
    <String, List<_PendingBusinessEntityWrite>>{};

final List<SyncChange> _pendingSyncChanges = <SyncChange>[];

final List<SyncQueueItem> _pendingSyncQueueItems = <SyncQueueItem>[];

Timer? _flushTimer;

bool _sqliteReady = false;

bool _sqliteDatabaseForTesting = false;

const Map<String, String> phase8AccountingSnapshotTables = <String, String>{
  'accountingAccounts': 'accounts',
  'accountingSettings': 'accounting_settings',
  'accountingPeriods': 'accounting_periods',
  'paymentAccounts': 'payment_accounts',
  'cashLocations': 'cash_locations',
  'cashDrawerSessions': 'cash_drawer_sessions',
  'cashTransfers': 'cash_transfers',
  'receiptVouchers': 'receipt_vouchers',
  'paymentVouchers': 'payment_vouchers',
  'paymentAllocations': 'payment_allocations',
  'cashRefundAllocations': 'cash_refund_allocations',
  'cashOperations': 'cash_operations',
  'cashLedgerTransactions': 'cash_ledger_transactions',
  'journalEntries': 'journal_entries',
  'journalLines': 'journal_lines',
  'accountingAuditLog': 'accounting_audit_log',
};

class LocalDatabaseService {
  LocalDatabaseService._();

  static final _LocalDatabaseServiceImplementation
      _localDatabaseServiceImplementation =
      _LocalDatabaseServiceImplementation();
  static const Map<String, String> phase8AccountingSnapshotTables =
      <String, String>{
    'accountingAccounts': 'accounts',
    'accountingSettings': 'accounting_settings',
    'accountingPeriods': 'accounting_periods',
    'paymentAccounts': 'payment_accounts',
    'cashLocations': 'cash_locations',
    'cashDrawerSessions': 'cash_drawer_sessions',
    'cashTransfers': 'cash_transfers',
    'receiptVouchers': 'receipt_vouchers',
    'paymentVouchers': 'payment_vouchers',
    'paymentAllocations': 'payment_allocations',
    'cashRefundAllocations': 'cash_refund_allocations',
    'cashOperations': 'cash_operations',
    'cashLedgerTransactions': 'cash_ledger_transactions',
    'journalEntries': 'journal_entries',
    'journalLines': 'journal_lines',
    'accountingAuditLog': 'accounting_audit_log',
  };
  static bool get isSqliteAuthoritative =>
      _localDatabaseServiceImplementation.isSqliteAuthoritative;

  static bool get isInMemoryStoreForTesting =>
      _localDatabaseServiceImplementation.isInMemoryStoreForTesting;

  static bool get isSqliteDatabaseForTesting =>
      _localDatabaseServiceImplementation.isSqliteDatabaseForTesting;

  static bool get hasPendingBusinessEntityWrites =>
      _localDatabaseServiceImplementation.hasPendingBusinessEntityWrites;

  static bool get canQueryBusinessSqlite =>
      _localDatabaseServiceImplementation.canQueryBusinessSqlite;

  @visibleForTesting
  static void useInMemoryStoreForTesting([Map<String, String>? seed]) =>
      _localDatabaseServiceImplementation.useInMemoryStoreForTesting(seed);

  @visibleForTesting
  static void clearInMemoryStoreForTesting() =>
      _localDatabaseServiceImplementation.clearInMemoryStoreForTesting();

  @visibleForTesting
  static Future<void> useSqliteDatabaseForTesting(
    VentioDriftDatabase db,
  ) =>
      _localDatabaseServiceImplementation.useSqliteDatabaseForTesting(db);

  @visibleForTesting
  static Future<void> resetForTesting() =>
      _localDatabaseServiceImplementation.resetForTesting();

  static Future<void> initialize() =>
      _localDatabaseServiceImplementation.initialize();

  static String? testingRawValue(String key) =>
      _localDatabaseServiceImplementation.testingRawValue(key);

  /// Loads the small set of device-bound secrets before the widget tree starts.
  /// Business/database initialization remains independently asynchronous.
  static Future<void> initializeSecureStorage() =>
      _localDatabaseServiceImplementation.initializeSecureStorage();

  static String? getSecureString(String key) =>
      _localDatabaseServiceImplementation.getSecureString(key);

  static Future<String?> readSecureString(String key) =>
      _localDatabaseServiceImplementation.readSecureString(key);

  static Future<void> setSecureString(String key, String value) =>
      _localDatabaseServiceImplementation.setSecureString(key, value);

  static Future<void> deleteSecureString(String key) =>
      _localDatabaseServiceImplementation.deleteSecureString(key);

  static String? getString(String key) =>
      _localDatabaseServiceImplementation.getString(key);

  static Future<List<StockMovement>?> getStockMovementsFromSqlite() =>
      _localDatabaseServiceImplementation.getStockMovementsFromSqlite();

  static Future<List<WarehouseInventory>?>
      getWarehouseInventoriesFromSqlite() => _localDatabaseServiceImplementation
          .getWarehouseInventoriesFromSqlite();

  static Future<List<InventoryReconciliation>?>
      getInventoryReconciliationsFromSqlite() =>
          _localDatabaseServiceImplementation
              .getInventoryReconciliationsFromSqlite();

  static Future<List<Map<String, dynamic>>?> getStockOperationsFromSqlite() =>
      _localDatabaseServiceImplementation.getStockOperationsFromSqlite();

  static Future<List<Map<String, dynamic>>?> getInventoryBatchesFromSqlite() =>
      _localDatabaseServiceImplementation.getInventoryBatchesFromSqlite();

  static Future<List<Map<String, dynamic>>?>
      getInventoryBatchBalancesFromSqlite() =>
          _localDatabaseServiceImplementation
              .getInventoryBatchBalancesFromSqlite();

  static Future<List<Map<String, dynamic>>?>
      getInventoryBatchReportFromSqlite() => _localDatabaseServiceImplementation
          .getInventoryBatchReportFromSqlite();

  /// Backward-compatible alias for older callers. The report is now the
  /// complete Unified Batch ledger, not expiry-only.
  static Future<List<Map<String, dynamic>>?> getExpiryBatchReportFromSqlite() =>
      _localDatabaseServiceImplementation.getExpiryBatchReportFromSqlite();

  static Future<void> replaceInventoryBatchRowsImmediate({
    required List<Map<String, dynamic>> batches,
    required List<Map<String, dynamic>> balances,
  }) =>
      _localDatabaseServiceImplementation.replaceInventoryBatchRowsImmediate(
          batches: batches, balances: balances);

  static Future<List<Map<String, dynamic>>?>
      getInventoryMigrationAdjustmentsFromSqlite() =>
          _localDatabaseServiceImplementation
              .getInventoryMigrationAdjustmentsFromSqlite();

  static Future<Map<String, List<Map<String, dynamic>>>>
      getPhase8AccountingSnapshotRows() =>
          _localDatabaseServiceImplementation.getPhase8AccountingSnapshotRows();

  static Future<void> replacePhase8AccountingSnapshotRowsImmediate(
    Map<String, List<Map<String, dynamic>>> collections,
  ) =>
      _localDatabaseServiceImplementation
          .replacePhase8AccountingSnapshotRowsImmediate(collections);

  static Future<Map<String, List<Map<String, dynamic>>>>
      getPhase8AccountingDeltaRows(DateTime since) =>
          _localDatabaseServiceImplementation
              .getPhase8AccountingDeltaRows(since);

  static Future<void> upsertPhase8AccountingSnapshotRowsImmediate(
    Map<String, List<Map<String, dynamic>>> collections,
  ) =>
      _localDatabaseServiceImplementation
          .upsertPhase8AccountingSnapshotRowsImmediate(collections);

  static Future<List<AccountTransaction>?> getAccountTransactionsFromSqlite() =>
      _localDatabaseServiceImplementation.getAccountTransactionsFromSqlite();

  static Future<List<Customer>?> getCustomersFromSqlite() =>
      _localDatabaseServiceImplementation.getCustomersFromSqlite();

  static Future<List<Product>?> getProductsFromSqlite() =>
      _localDatabaseServiceImplementation.getProductsFromSqlite();

  static Future<List<Sale>?> getSalesFromSqlite() =>
      _localDatabaseServiceImplementation.getSalesFromSqlite();

  static Future<BusinessQueryPage<Sale>?> querySalesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) =>
      _localDatabaseServiceImplementation.querySalesFromSqlite(
          query: query,
          status: status,
          customerId: customerId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<BusinessQueryPage<SaleSummary>?> querySaleSummariesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) =>
      _localDatabaseServiceImplementation.querySaleSummariesFromSqlite(
          query: query,
          status: status,
          customerId: customerId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<Map<String, Object?>?> assistantSalesSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) =>
      _localDatabaseServiceImplementation.assistantSalesSummaryFromSqlite(
          from: from, to: to);

  static Future<Sale?> getSaleFromSqliteById(String id) =>
      _localDatabaseServiceImplementation.getSaleFromSqliteById(id);

  static Future<List<Sale>?> queryEligibleDeliveryNoteSalesFromSqlite({
    int limit = 100,
  }) =>
      _localDatabaseServiceImplementation
          .queryEligibleDeliveryNoteSalesFromSqlite(limit: limit);

  static Future<List<SaleQuotation>?> getSaleQuotationsFromSqlite() =>
      _localDatabaseServiceImplementation.getSaleQuotationsFromSqlite();

  static Future<List<DeliveryNote>?> getDeliveryNotesFromSqlite() =>
      _localDatabaseServiceImplementation.getDeliveryNotesFromSqlite();

  static Future<List<Supplier>?> getSuppliersFromSqlite() =>
      _localDatabaseServiceImplementation.getSuppliersFromSqlite();

  static Future<Expense?> getExpenseFromSqliteById(String id) =>
      _localDatabaseServiceImplementation.getExpenseFromSqliteById(id);

  static Future<List<Expense>?> getExpensesFromSqlite() =>
      _localDatabaseServiceImplementation.getExpensesFromSqlite();

  static Future<List<Warehouse>?> getWarehousesFromSqlite() =>
      _localDatabaseServiceImplementation.getWarehousesFromSqlite();

  static Future<List<Purchase>?> getPurchasesFromSqlite() =>
      _localDatabaseServiceImplementation.getPurchasesFromSqlite();

  static Future<BusinessQueryPage<Purchase>?> queryPurchasesFromSqlite({
    String query = '',
    String status = 'all',
    String supplierId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) =>
      _localDatabaseServiceImplementation.queryPurchasesFromSqlite(
          query: query,
          status: status,
          supplierId: supplierId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<Map<String, Object?>?> assistantPurchaseSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) =>
      _localDatabaseServiceImplementation.assistantPurchaseSummaryFromSqlite(
          from: from, to: to);

  static Future<Map<String, Object?>?> buildPurchasesOverviewFromSqlite({
    DateTime? reference,
  }) =>
      _localDatabaseServiceImplementation.buildPurchasesOverviewFromSqlite(
          reference: reference);

  static Future<Purchase?> getPurchaseFromSqliteById(String id) =>
      _localDatabaseServiceImplementation.getPurchaseFromSqliteById(id);

  static Future<List<InventoryCountSession>?> getInventoryCountsFromSqlite() =>
      _localDatabaseServiceImplementation.getInventoryCountsFromSqlite();

  static Future<Map<String, Object?>?> assistantStockBalancesFromSqlite({
    required String storeId,
    String productQuery = '',
    String warehouseQuery = '',
  }) =>
      _localDatabaseServiceImplementation.assistantStockBalancesFromSqlite(
          storeId: storeId,
          productQuery: productQuery,
          warehouseQuery: warehouseQuery);

  static Future<Map<String, Object?>?> assistantStockMovementSummaryFromSqlite({
    required String storeId,
    required DateTime from,
    required DateTime to,
    String productQuery = '',
    String warehouseQuery = '',
    String type = 'all',
  }) =>
      _localDatabaseServiceImplementation
          .assistantStockMovementSummaryFromSqlite(
              storeId: storeId,
              from: from,
              to: to,
              productQuery: productQuery,
              warehouseQuery: warehouseQuery,
              type: type);

  static Future<BusinessQueryPage<StockMovement>?>
      queryStockMovementsFromSqlite({
    String query = '',
    String type = 'all',
    String productId = '',
    String warehouseId = '',
    DateTime? from,
    DateTime? to,
    bool? reviewed,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) =>
          _localDatabaseServiceImplementation.queryStockMovementsFromSqlite(
              query: query,
              type: type,
              productId: productId,
              warehouseId: warehouseId,
              from: from,
              to: to,
              reviewed: reviewed,
              limit: limit,
              offset: offset,
              sortMode: sortMode);

  static Future<BusinessQueryPage<StockMovement>?> queryWasteLossFromSqlite({
    int limit = 50,
    int offset = 0,
  }) =>
      _localDatabaseServiceImplementation.queryWasteLossFromSqlite(
          limit: limit, offset: offset);

  static Future<Map<String, int>?> countStockMovementsAfterByProductFromSqlite(
    Map<String, DateTime> countedAtByProduct,
  ) =>
      _localDatabaseServiceImplementation
          .countStockMovementsAfterByProductFromSqlite(countedAtByProduct);

  static Future<List<BillOfMaterials>?> getBillOfMaterialsFromSqlite() =>
      _localDatabaseServiceImplementation.getBillOfMaterialsFromSqlite();

  static Future<List<ManufacturingOrder>?> getManufacturingOrdersFromSqlite() =>
      _localDatabaseServiceImplementation.getManufacturingOrdersFromSqlite();

  static Future<List<CatalogItem>?> getCatalogItemsFromSqlite(String key) =>
      _localDatabaseServiceImplementation.getCatalogItemsFromSqlite(key);

  static Future<List<SupplierProductPrice>?>
      getSupplierProductPricesFromSqlite() =>
          _localDatabaseServiceImplementation
              .getSupplierProductPricesFromSqlite();

  static Future<List<PriceList>?> getPriceListsFromSqlite() =>
      _localDatabaseServiceImplementation.getPriceListsFromSqlite();

  static Future<List<ProductPrice>?> getProductPricesFromSqlite() =>
      _localDatabaseServiceImplementation.getProductPricesFromSqlite();

  static Future<List<ProductPriceHistoryEntry>?>
      getProductPriceHistoryFromSqlite({
    String productId = '',
    int limit = 200,
  }) =>
          _localDatabaseServiceImplementation.getProductPriceHistoryFromSqlite(
              productId: productId, limit: limit);

  static Future<List<ProductPriceOverride>?>
      getProductPriceOverridesFromSqlite() =>
          _localDatabaseServiceImplementation
              .getProductPriceOverridesFromSqlite();

  static Future<List<ProductCost>?> getProductCostsFromSqlite() =>
      _localDatabaseServiceImplementation.getProductCostsFromSqlite();

  static Future<List<CostingMethodHistory>?>
      getCostingMethodHistoryFromSqlite() => _localDatabaseServiceImplementation
          .getCostingMethodHistoryFromSqlite();

  static Future<List<InventoryCostLayer>?> getInventoryCostLayersFromSqlite() =>
      _localDatabaseServiceImplementation.getInventoryCostLayersFromSqlite();

  static Future<BusinessQueryPage<Customer>?> queryCustomersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
    bool includeWalkIn = false,
  }) =>
      _localDatabaseServiceImplementation.queryCustomersFromSqlite(
          query: query,
          limit: limit,
          offset: offset,
          includeWalkIn: includeWalkIn);

  static Future<BusinessQueryPage<Supplier>?> querySuppliersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) =>
      _localDatabaseServiceImplementation.querySuppliersFromSqlite(
          query: query, limit: limit, offset: offset);

  static Future<BusinessQueryPage<Expense>?> queryExpensesFromSqlite({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) =>
      _localDatabaseServiceImplementation.queryExpensesFromSqlite(
          query: query, status: status, limit: limit, offset: offset);

  static Future<double?> sumPostedExpensesFromSqlite({
    String query = '',
    String status = 'all',
  }) =>
      _localDatabaseServiceImplementation.sumPostedExpensesFromSqlite(
          query: query, status: status);

  static Future<Map<String, Object?>?> assistantExpenseSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) =>
      _localDatabaseServiceImplementation.assistantExpenseSummaryFromSqlite(
          from: from, to: to);

  static Future<BusinessQueryPage<Product>?> queryProductsFromSqlite({
    String query = '',
    String category = '',
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
    bool stockTrackedOnly = false,
  }) =>
      _localDatabaseServiceImplementation.queryProductsFromSqlite(
          query: query,
          category: category,
          limit: limit,
          offset: offset,
          activeOnly: activeOnly,
          stockTrackedOnly: stockTrackedOnly);

  static Future<Map<String, Object?>?> findSaleBarcodeProductFromSqlite(
    String code,
  ) =>
      _localDatabaseServiceImplementation
          .findSaleBarcodeProductFromSqlite(code);

  static Future<List<String>?> queryProductCategoriesFromSqlite() =>
      _localDatabaseServiceImplementation.queryProductCategoriesFromSqlite();

  static Future<Map<String, Object?>?> buildDashboardSummaryFromSqlite({
    required DateTime reference,
  }) =>
      _localDatabaseServiceImplementation.buildDashboardSummaryFromSqlite(
          reference: reference);

  static Future<Map<String, Object?>?> buildReportsSummaryFromSqlite({
    required DateTime reference,
  }) =>
      _localDatabaseServiceImplementation.buildReportsSummaryFromSqlite(
          reference: reference);

  static Future<Map<String, Object?>?> buildAccountingMetricsFromSqlite({
    required DateTime reference,
  }) =>
      _localDatabaseServiceImplementation.buildAccountingMetricsFromSqlite(
          reference: reference);

  static Future<List<Map<String, Object?>>?>
      queryAccountingAccountRowsFromSqlite({
    required String accountType,
    String query = '',
    int limit = 200,
  }) =>
          _localDatabaseServiceImplementation
              .queryAccountingAccountRowsFromSqlite(
                  accountType: accountType, query: query, limit: limit);

  static Future<void> upsertBusinessEntityJson(
          String key, Map<String, dynamic> payloadJson, {int? sortIndex}) =>
      _localDatabaseServiceImplementation
          .upsertBusinessEntityJson(key, payloadJson, sortIndex: sortIndex);

  static Future<void> upsertBusinessEntityJsons(
    String key,
    List<Map<String, dynamic>> payloadJsons, {
    List<int?>? sortIndices,
  }) =>
      _localDatabaseServiceImplementation.upsertBusinessEntityJsons(
          key, payloadJsons,
          sortIndices: sortIndices);

  static Future<void> upsertSyncChange(SyncChange change) =>
      _localDatabaseServiceImplementation.upsertSyncChange(change);

  static Future<void> upsertSyncChanges(List<SyncChange> changes) =>
      _localDatabaseServiceImplementation.upsertSyncChanges(changes);

  static Future<void> upsertSyncQueueItem(SyncQueueItem item) =>
      _localDatabaseServiceImplementation.upsertSyncQueueItem(item);

  static Future<void> upsertSyncQueueItems(List<SyncQueueItem> items) =>
      _localDatabaseServiceImplementation.upsertSyncQueueItems(items);

  static Future<void> setString(String key, String value) =>
      _localDatabaseServiceImplementation.setString(key, value);

  static bool containsKey(String key) =>
      _localDatabaseServiceImplementation.containsKey(key);

  static Future<void> deleteString(String key) =>
      _localDatabaseServiceImplementation.deleteString(key);

  static Future<void> clearAll() =>
      _localDatabaseServiceImplementation.clearAll();

  static Future<void> flushPendingWrites() =>
      _localDatabaseServiceImplementation.flushPendingWrites();

  static Future<void> runSqliteAuthoritativeTransaction(
          Future<void> Function() action) =>
      _localDatabaseServiceImplementation
          .runSqliteAuthoritativeTransaction(action);

  /// Rehydrates the SQLite scalar mirror from the committed database state.
  ///
  /// Immediate snapshot writes update the in-memory mirror while a Drift
  /// transaction is still open. If that transaction rolls back, SQLite is
  /// correct but the mirror would otherwise keep the rejected values. Call
  /// this after an authoritative transaction failure before exposing runtime
  /// state again.
  static Future<void> refreshSqliteMirrorAfterRollback() =>
      _localDatabaseServiceImplementation.refreshSqliteMirrorAfterRollback();

  static Future<void> replaceBusinessEntityJsonListImmediate(
          String key, List<Map<String, dynamic>> payloads,
          {List<int?>? sortIndices}) =>
      _localDatabaseServiceImplementation
          .replaceBusinessEntityJsonListImmediate(key, payloads,
              sortIndices: sortIndices);

  static Future<void> replaceWarehouseInventoryRowsImmediate(
          List<Map<String, dynamic>> rows,
          {bool allowNegativeStock = false}) =>
      _localDatabaseServiceImplementation
          .replaceWarehouseInventoryRowsImmediate(rows,
              allowNegativeStock: allowNegativeStock);

  static Future<void> replaceStockOperationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) =>
      _localDatabaseServiceImplementation
          .replaceStockOperationsRowsImmediate(rows);

  static Future<void> replaceStockMovementRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) =>
      _localDatabaseServiceImplementation
          .replaceStockMovementRowsImmediate(rows);

  static Future<void> replaceInventoryReconciliationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) =>
      _localDatabaseServiceImplementation
          .replaceInventoryReconciliationsRowsImmediate(rows);

  static Future<void> replaceInventoryMigrationAdjustmentsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) =>
      _localDatabaseServiceImplementation
          .replaceInventoryMigrationAdjustmentsRowsImmediate(rows);

  static List<String> keys() => _localDatabaseServiceImplementation.keys();

  static Map<String, String> allEntries() =>
      _localDatabaseServiceImplementation.allEntries();

  /// Full diagnostic/admin snapshot for the Database page.
  ///
  /// `allEntries()` intentionally stays startup-fast after SQLite became
  /// authoritative and only returns the scalar mirror. The Database page,
  /// however, is an explicit admin browser and must show the real typed SQLite
  /// tables as well. This method hydrates those tables on demand.
  static Future<Map<String, String>> adminEntries() =>
      _localDatabaseServiceImplementation.adminEntries();

  static Future<int> pendingSyncQueueCountForTarget(
    String target, {
    bool readyOnly = true,
  }) =>
      _localDatabaseServiceImplementation.pendingSyncQueueCountForTarget(target,
          readyOnly: readyOnly);

  static Future<int> pendingSyncChangesCount() =>
      _localDatabaseServiceImplementation.pendingSyncChangesCount();

  static Future<int> outstandingSyncQueueCountForTarget(String target) =>
      _localDatabaseServiceImplementation
          .outstandingSyncQueueCountForTarget(target);

  static bool get isEmpty => _localDatabaseServiceImplementation.isEmpty;
}

class _LocalDatabaseServiceImplementation {}

class _PendingBusinessEntityWrite {
  const _PendingBusinessEntityWrite({
    required this.payload,
  });

  final Map<String, dynamic> payload;
}
