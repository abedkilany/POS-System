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
import '../../models/sale_summary.dart';
import '../../models/stock_movement.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/warehouse.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

VentioDriftDatabase? _businessDb() => SqliteMigrationManager.database;

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

  static Future<List<Product>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readProducts(db);
  }

  static Future<List<String>?> getCategories() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.queryProductCategories(db);
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

  static Future<List<Customer>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readCustomers(db);
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

  static Future<List<Supplier>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSuppliers(db);
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

  static Future<List<Sale>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSales(db);
  }

  static Future<Sale?> getById(String id) async {
    final db = _businessDb();
    if (db == null) return null;
    final results = await BusinessSqliteStore.readSalesByIds(db, <String>[id]);
    return results.isEmpty ? null : results.first;
  }

  static Future<List<SaleQuotation>?> getQuotations() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readSaleQuotations(db);
  }

  static Future<List<DeliveryNote>?> getDeliveryNotes() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readDeliveryNotes(db);
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

  static Future<List<Expense>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readExpenses(db);
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
    if (db == null) return null;
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

  static Future<List<Purchase>?> getAll() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readPurchases(db);
  }
}

class InventoryRepository {
  InventoryRepository._();

  static Future<List<StockMovement>?> getStockMovements() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readStockMovements(db);
  }

  static Future<List<InventoryCountSession>?> getInventoryCounts() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readInventoryCounts(db);
  }

  static Future<List<Warehouse>?> getWarehouses() async {
    final db = _businessDb();
    if (db == null) return null;
    return BusinessSqliteStore.readWarehouses(db);
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
    if (db == null) return null;
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
}
