// ignore_for_file: unused_import
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../models/account_transaction.dart';
import '../../../models/catalog_item.dart';
import '../../../models/customer.dart';
import '../../../models/delivery_note.dart';
import '../../../models/expense.dart';
import '../../../models/inventory_count.dart';
import '../../../models/inventory_cost_layer.dart';
import '../../../models/manufacturing.dart';
import '../../../models/product.dart';
import '../../../models/product_costing.dart';
import '../../../models/product_pricing.dart';
import '../../../models/purchase.dart';
import '../../../models/sale.dart';
import '../../../models/sale_quotation.dart';
import '../../../models/sale_summary.dart';
import '../../../models/user_role.dart';
import '../../../models/supplier.dart';
import '../../../models/supplier_product_price.dart';
import '../../../models/stock_movement.dart';
import '../../../models/warehouse.dart';
import '../../../models/warehouse_transfer_order.dart';
import '../../../models/app_user.dart';
import 'sync_sqlite_store.dart';
import 'ventio_drift_database.dart';
import 'business_sqlite_store_impl.dart' as impl;
import 'business_sqlite_store_models.dart';
export 'business_sqlite_store_models.dart';

class BusinessSqliteStore {
  BusinessSqliteStore._();

  static const String phase3MigratedMetaKey = 'sqlite_phase3_business_migrated';

  static const String phase3TypedTablesMetaKey =
      'sqlite_phase3_typed_tables_migrated';

  static const String phase3ComplexTablesMetaKey =
      'sqlite_phase3_complex_tables_migrated';

  static const String phase3ValidatedMetaKey =
      'sqlite_phase3_validation_passed';

  static const String productsKey = 'products_v4';

  static const String customersKey = 'customers_v4';

  static const String salesKey = 'sales_v4';

  static const String saleQuotationsKey = 'sale_quotations_v1';

  static const String deliveryNotesKey = 'delivery_notes_v1';

  static const String billsOfMaterialsKey = 'bills_of_materials_v1';

  static const String manufacturingOrdersKey = 'manufacturing_orders_v1';

  static const String suppliersKey = 'suppliers_v4';

  static const String supplierProductPricesKey = 'supplier_product_prices_v1';

  static const String priceListsKey = 'price_lists_v1';

  static const String productPricesKey = 'product_prices_v1';

  static const String productPriceHistoryKey = 'product_price_history_v1';

  static const String productPriceOverridesKey = 'product_price_overrides_v1';

  static const String productCostsKey = 'product_costs_v1';

  static const String costingMethodHistoryKey = 'costing_method_history_v1';

  static const String inventoryCostLayersKey = 'inventory_cost_layers_v1';

  static const String expensesKey = 'expenses_v4';

  static const String purchasesKey = 'purchases_v1';

  static const String inventoryCountsKey = 'inventory_counts_v1';

  static const String warehousesKey = 'warehouses_v1';

  static const String warehouseTransferOrdersKey =
      'warehouse_transfer_orders_v1';

  static const String stockMovementsKey = 'stock_movements_v1';

  static const String accountTransactionsKey = 'account_transactions_v1';

  static const String categoriesKey = 'product_categories_v1';

  static const String brandsKey = 'product_brands_v1';

  static const String unitsKey = 'product_units_v1';

  static const String rolesKey = 'roles_v1';

  static const String usersKey = 'users_v1';

  static bool isBusinessKey(String key) => impl.isBusinessKey(key);

  static bool isTypedEntityKey(String key) => impl.isTypedEntityKey(key);

  static List<String> get adminEntityKeys => impl.adminEntityKeys;

  static Future<BusinessQueryPage<Customer>> queryCustomers(
          VentioDriftDatabase db,
          {String query = '',
          int limit = 50,
          int offset = 0,
          bool includeWalkIn = false}) =>
      impl.queryCustomers(db,
          query: query,
          limit: limit,
          offset: offset,
          includeWalkIn: includeWalkIn);

  static Future<BusinessQueryPage<Supplier>> querySuppliers(
          VentioDriftDatabase db,
          {String query = '',
          int limit = 50,
          int offset = 0}) =>
      impl.querySuppliers(db, query: query, limit: limit, offset: offset);

  static Future<BusinessQueryPage<Expense>> queryExpenses(
          VentioDriftDatabase db,
          {String query = '',
          String status = 'all',
          int limit = 50,
          int offset = 0}) =>
      impl.queryExpenses(db,
          query: query, status: status, limit: limit, offset: offset);

  static Future<double> sumPostedExpenses(VentioDriftDatabase db,
          {String query = '', String status = 'all'}) =>
      impl.sumPostedExpenses(db, query: query, status: status);

  static Future<Map<String, Object?>> assistantExpenseSummary(
          VentioDriftDatabase db,
          {required DateTime from,
          required DateTime to}) =>
      impl.assistantExpenseSummary(db, from: from, to: to);

  static Future<BusinessQueryPage<Product>> queryProducts(
          VentioDriftDatabase db,
          {String query = '',
          String category = '',
          int limit = 50,
          int offset = 0,
          bool activeOnly = false,
          bool stockTrackedOnly = false}) =>
      impl.queryProducts(db,
          query: query,
          category: category,
          limit: limit,
          offset: offset,
          activeOnly: activeOnly,
          stockTrackedOnly: stockTrackedOnly);

  static Future<List<String>> queryProductCategories(VentioDriftDatabase db) =>
      impl.queryProductCategories(db);

  static Future<Map<String, Object?>> buildDashboardSummary(
          VentioDriftDatabase db,
          {required DateTime reference}) =>
      impl.buildDashboardSummary(db, reference: reference);

  static Future<Map<String, Object?>> buildReportsSummary(
          VentioDriftDatabase db,
          {required DateTime reference}) =>
      impl.buildReportsSummary(db, reference: reference);

  static Future<Map<String, Object?>> buildAccountingMetrics(
          VentioDriftDatabase db,
          {required DateTime reference}) =>
      impl.buildAccountingMetrics(db, reference: reference);

  static Future<List<Map<String, Object?>>> queryAccountingAccountRows(
          VentioDriftDatabase db,
          {required String accountType,
          String query = '',
          int limit = 200}) =>
      impl.queryAccountingAccountRows(db,
          accountType: accountType, query: query, limit: limit);

  static Future<void> refreshSummaryTables(VentioDriftDatabase db,
          {required DateTime reference, bool force = false}) =>
      impl.refreshSummaryTables(db, reference: reference, force: force);

  static Future<void> refreshDailyMetrics(VentioDriftDatabase db) =>
      impl.refreshDailyMetrics(db);

  static Future<void> migrateFromLegacyJsonIfNeeded(VentioDriftDatabase db,
          {required Map<String, String> legacyEntries}) =>
      impl.migrateFromLegacyJsonIfNeeded(db, legacyEntries: legacyEntries);

  static Future<void> markFreshInstallValidated(VentioDriftDatabase db) =>
      impl.markFreshInstallValidated(db);

  static Future<void> migrateComplexTablesFromPayloadJson(
          VentioDriftDatabase db) =>
      impl.migrateComplexTablesFromPayloadJson(db);

  static Future<bool> isValidationPassed(VentioDriftDatabase db) =>
      impl.isValidationPassed(db);

  static Future<Map<String, String>> hydrateKeyMirror(VentioDriftDatabase db) =>
      impl.hydrateKeyMirror(db);

  static Future<Map<String, String>> hydrateScalarKeyMirror(
          VentioDriftDatabase db) =>
      impl.hydrateScalarKeyMirror(db);

  static Future<String?> readEntityListJsonByKey(
          VentioDriftDatabase db, String key) =>
      impl.readEntityListJsonByKey(db, key);

  static Future<List<String>> readEntityListJsonBatches(
          VentioDriftDatabase db, String key,
          {int batchSize = 100}) =>
      impl.readEntityListJsonBatches(db, key, batchSize: batchSize);

  static Future<List<StockMovement>> readStockMovements(
          VentioDriftDatabase db) =>
      impl.readStockMovements(db);

  static Future<BusinessQueryPage<StockMovement>> queryStockMovements(
          VentioDriftDatabase db,
          {String query = '',
          String type = 'all',
          String productId = '',
          String warehouseId = '',
          DateTime? from,
          DateTime? to,
          bool? reviewed,
          int limit = 50,
          int offset = 0,
          String sortMode = 'newest'}) =>
      impl.queryStockMovements(db,
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

  static Future<Map<String, Object?>> assistantStockBalances(
          VentioDriftDatabase db,
          {String storeId = '',
          String productQuery = '',
          String warehouseQuery = ''}) =>
      impl.assistantStockBalances(db,
          storeId: storeId,
          productQuery: productQuery,
          warehouseQuery: warehouseQuery);

  static Future<Map<String, Object?>> assistantStockMovementSummary(
          VentioDriftDatabase db,
          {required DateTime from,
          required DateTime to,
          String storeId = '',
          String productQuery = '',
          String warehouseQuery = '',
          String type = 'all'}) =>
      impl.assistantStockMovementSummary(db,
          from: from,
          to: to,
          storeId: storeId,
          productQuery: productQuery,
          warehouseQuery: warehouseQuery,
          type: type);

  static Future<BusinessQueryPage<StockMovement>> queryWasteLossMovements(
          VentioDriftDatabase db,
          {int limit = 50,
          int offset = 0}) =>
      impl.queryWasteLossMovements(db, limit: limit, offset: offset);

  static Future<List<StockMovement>> readUnreversedInventoryCountMovements(
          VentioDriftDatabase db, String inventoryCountId) =>
      impl.readUnreversedInventoryCountMovements(db, inventoryCountId);

  static Future<Map<String, int>> countStockMovementsAfterByProduct(
          VentioDriftDatabase db, Map<String, DateTime> countedAtByProduct) =>
      impl.countStockMovementsAfterByProduct(db, countedAtByProduct);

  static Future<List<AccountTransaction>> readAccountTransactions(
          VentioDriftDatabase db) =>
      impl.readAccountTransactions(db);

  static Future<List<Customer>> readCustomers(VentioDriftDatabase db) =>
      impl.readCustomers(db);

  static Future<List<Supplier>> readSuppliers(VentioDriftDatabase db) =>
      impl.readSuppliers(db);

  static Future<Expense?> readExpenseById(VentioDriftDatabase db, String id) =>
      impl.readExpenseById(db, id);

  static Future<List<Expense>> readExpenses(VentioDriftDatabase db) =>
      impl.readExpenses(db);

  static Future<List<Warehouse>> readWarehouses(VentioDriftDatabase db) =>
      impl.readWarehouses(db);

  static Future<List<WarehouseTransferOrder>> readWarehouseTransferOrders(
          VentioDriftDatabase db,
          {int? limit}) =>
      impl.readWarehouseTransferOrders(db, limit: limit);

  static Future<List<CatalogItem>> readCatalogItems(
          VentioDriftDatabase db, String table) =>
      impl.readCatalogItems(db, table);

  static Future<List<UserRole>> readRoles(VentioDriftDatabase db) =>
      impl.readRoles(db);

  static Future<List<AppUser>> readUsers(VentioDriftDatabase db) =>
      impl.readUsers(db);

  static Future<List<PriceList>> readPriceLists(VentioDriftDatabase db) =>
      impl.readPriceLists(db);

  static Future<List<ProductPrice>> readProductPrices(VentioDriftDatabase db) =>
      impl.readProductPrices(db);

  static Future<List<ProductPriceHistoryEntry>> readProductPriceHistory(
          VentioDriftDatabase db,
          {String productId = '',
          int limit = 200}) =>
      impl.readProductPriceHistory(db, productId: productId, limit: limit);

  static Future<List<ProductPriceOverride>> readProductPriceOverrides(
          VentioDriftDatabase db) =>
      impl.readProductPriceOverrides(db);

  static Future<List<ProductCost>> readProductCosts(VentioDriftDatabase db) =>
      impl.readProductCosts(db);

  static Future<List<CostingMethodHistory>> readCostingMethodHistory(
          VentioDriftDatabase db) =>
      impl.readCostingMethodHistory(db);

  static Future<List<InventoryCostLayer>> readInventoryCostLayers(
          VentioDriftDatabase db) =>
      impl.readInventoryCostLayers(db);

  static Future<List<SupplierProductPrice>> readSupplierProductPrices(
          VentioDriftDatabase db) =>
      impl.readSupplierProductPrices(db);

  static Future<List<Product>> readProducts(VentioDriftDatabase db) =>
      impl.readProducts(db);

  static Future<Product?> readProductById(
          VentioDriftDatabase db, String productId) =>
      impl.readProductById(db, productId);

  static Future<Map<String, Object?>?> findSaleBarcodeProduct(
          VentioDriftDatabase db, String code) =>
      impl.findSaleBarcodeProduct(db, code);

  static Future<List<Sale>> readSales(VentioDriftDatabase db) =>
      impl.readSales(db);

  static Future<List<Sale>> readSalesByIds(
          VentioDriftDatabase db, List<String> ids) =>
      impl.readSalesByIds(db, ids);

  static Future<List<Sale>> queryEligibleDeliveryNoteSales(
          VentioDriftDatabase db,
          {int limit = 100}) =>
      impl.queryEligibleDeliveryNoteSales(db, limit: limit);

  static Future<BusinessQueryPage<Sale>> querySales(VentioDriftDatabase db,
          {String query = '',
          String status = 'all',
          String customerId = '',
          DateTime? from,
          DateTime? to,
          int limit = 50,
          int offset = 0,
          String sortMode = 'newest'}) =>
      impl.querySales(db,
          query: query,
          status: status,
          customerId: customerId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<List<SaleQuotation>> readSaleQuotations(
          VentioDriftDatabase db) =>
      impl.readSaleQuotations(db);

  static Future<List<DeliveryNote>> readDeliveryNotes(VentioDriftDatabase db) =>
      impl.readDeliveryNotes(db);

  static Future<List<Purchase>> readPurchases(VentioDriftDatabase db) =>
      impl.readPurchases(db);

  static Future<List<Purchase>> readPurchasesByIds(
          VentioDriftDatabase db, List<String> ids) =>
      impl.readPurchasesByIds(db, ids);

  static Future<BusinessQueryPage<Purchase>> queryPurchases(
          VentioDriftDatabase db,
          {String query = '',
          String status = 'all',
          String supplierId = '',
          DateTime? from,
          DateTime? to,
          int limit = 50,
          int offset = 0,
          String sortMode = 'newest'}) =>
      impl.queryPurchases(db,
          query: query,
          status: status,
          supplierId: supplierId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<BusinessQueryPage<SaleSummary>> querySaleSummaries(
          VentioDriftDatabase db,
          {String query = '',
          String status = 'all',
          String customerId = '',
          DateTime? from,
          DateTime? to,
          int limit = 50,
          int offset = 0,
          String sortMode = 'newest'}) =>
      impl.querySaleSummaries(db,
          query: query,
          status: status,
          customerId: customerId,
          from: from,
          to: to,
          limit: limit,
          offset: offset,
          sortMode: sortMode);

  static Future<Map<String, Object?>> assistantSalesSummary(
          VentioDriftDatabase db,
          {required DateTime from,
          required DateTime to}) =>
      impl.assistantSalesSummary(db, from: from, to: to);

  static Future<Map<String, Object?>> assistantPurchaseSummary(
          VentioDriftDatabase db,
          {required DateTime from,
          required DateTime to}) =>
      impl.assistantPurchaseSummary(db, from: from, to: to);

  static Future<Map<String, Object?>> buildPurchasesOverview(
          VentioDriftDatabase db,
          {required DateTime reference}) =>
      impl.buildPurchasesOverview(db, reference: reference);

  static Future<List<InventoryCountSession>> readInventoryCounts(
          VentioDriftDatabase db) =>
      impl.readInventoryCounts(db);

  static Future<List<BillOfMaterials>> readBillOfMaterials(
          VentioDriftDatabase db) =>
      impl.readBillOfMaterials(db);

  static Future<List<ManufacturingOrder>> readManufacturingOrders(
          VentioDriftDatabase db) =>
      impl.readManufacturingOrders(db);

  static Future<void> saveKeyJson(
          VentioDriftDatabase db, String key, String value) =>
      impl.saveKeyJson(db, key, value);

  static Future<void> upsertEntityPayload(
          VentioDriftDatabase db, String key, Map<String, dynamic> payload,
          {int? sortIndex}) =>
      impl.upsertEntityPayload(db, key, payload, sortIndex: sortIndex);

  static Future<void> upsertEntityPayloads(VentioDriftDatabase db, String key,
          List<Map<String, dynamic>> payloads,
          {List<int?>? sortIndices}) =>
      impl.upsertEntityPayloads(db, key, payloads, sortIndices: sortIndices);

  static Future<void> upsertInventoryCountInTransaction(
          VentioDriftDatabase db, InventoryCountSession session) =>
      impl.upsertInventoryCountInTransaction(db, session);

  static Future<void> upsertManufacturingOrderPayloadInTransaction(
          VentioDriftDatabase db, Map<String, dynamic> payload,
          {required String id,
          required String payloadJson,
          required String createdAt,
          required String updatedAt,
          required String deletedAt,
          required int sortIndex}) =>
      impl.upsertManufacturingOrderPayloadInTransaction(db, payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex);

  static Future<void> upsertBillOfMaterialsPayloadInTransaction(
          VentioDriftDatabase db, Map<String, dynamic> payload,
          {required String id,
          required String payloadJson,
          required String createdAt,
          required String updatedAt,
          required String deletedAt,
          required int sortIndex}) =>
      impl.upsertBillOfMaterialsPayloadInTransaction(db, payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex);

  static Future<void> deleteKey(VentioDriftDatabase db, String key) =>
      impl.deleteKey(db, key);

  static Future<void> clear(VentioDriftDatabase db) => impl.clear(db);

  static Future<BusinessSqliteValidationResult> validateAgainstLegacyJson(
          VentioDriftDatabase db,
          {required Map<String, String> legacyEntries}) =>
      impl.validateAgainstLegacyJson(db, legacyEntries: legacyEntries);
}
