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
import 'business_sqlite_store_models.dart';

part 'business_sqlite_store_queries.dart';
part 'business_sqlite_store_summary_and_migrations.dart';
part 'business_sqlite_store_entity_reads.dart';
part 'business_sqlite_store_stock_movements.dart';
part 'business_sqlite_store_entity_readers.dart';
part 'business_sqlite_store_sales_reads.dart';
part 'business_sqlite_store_purchase_reports.dart';
part 'business_sqlite_store_payload_batches.dart';
part 'business_sqlite_store_entity_upserts.dart';
part 'business_sqlite_store_domain_upserts.dart';
part 'business_sqlite_store_migration_validation.dart';
part 'business_sqlite_store_sql_helpers.dart';
part 'business_sqlite_store_internal_types.dart';

final Map<String, Future<Set<String>>> _tableColumnFutures =
    <String, Future<Set<String>>>{};

const String phase3MigratedMetaKey = 'sqlite_phase3_business_migrated';

const String phase3TypedTablesMetaKey = 'sqlite_phase3_typed_tables_migrated';

const String phase3ComplexTablesMetaKey =
    'sqlite_phase3_complex_tables_migrated';

const String phase3ValidatedMetaKey = 'sqlite_phase3_validation_passed';

const String productsKey = 'products_v4';

const String customersKey = 'customers_v4';

const String salesKey = 'sales_v4';

const String saleQuotationsKey = 'sale_quotations_v1';

const String deliveryNotesKey = 'delivery_notes_v1';

const String billsOfMaterialsKey = 'bills_of_materials_v1';

const String manufacturingOrdersKey = 'manufacturing_orders_v1';

const String suppliersKey = 'suppliers_v4';

const String supplierProductPricesKey = 'supplier_product_prices_v1';

const String priceListsKey = 'price_lists_v1';

const String productPricesKey = 'product_prices_v1';

const String productPriceHistoryKey = 'product_price_history_v1';

const String productPriceOverridesKey = 'product_price_overrides_v1';

const String productCostsKey = 'product_costs_v1';

const String costingMethodHistoryKey = 'costing_method_history_v1';

const String inventoryCostLayersKey = 'inventory_cost_layers_v1';

const String expensesKey = 'expenses_v4';

const String purchasesKey = 'purchases_v1';

const String inventoryCountsKey = 'inventory_counts_v1';

const String warehousesKey = 'warehouses_v1';

const String warehouseTransferOrdersKey = 'warehouse_transfer_orders_v1';

const String stockMovementsKey = 'stock_movements_v1';

const String accountTransactionsKey = 'account_transactions_v1';

const String categoriesKey = 'product_categories_v1';

const String brandsKey = 'product_brands_v1';

const String unitsKey = 'product_units_v1';

const String rolesKey = 'roles_v1';

const String usersKey = 'users_v1';

const Set<String> _entityListKeys = <String>{
  productsKey,
  customersKey,
  salesKey,
  saleQuotationsKey,
  deliveryNotesKey,
  billsOfMaterialsKey,
  manufacturingOrdersKey,
  suppliersKey,
  supplierProductPricesKey,
  priceListsKey,
  productPricesKey,
  productPriceHistoryKey,
  productPriceOverridesKey,
  productCostsKey,
  costingMethodHistoryKey,
  inventoryCostLayersKey,
  expensesKey,
  purchasesKey,
  inventoryCountsKey,
  warehousesKey,
  warehouseTransferOrdersKey,
  stockMovementsKey,
  accountTransactionsKey,
  categoriesKey,
  brandsKey,
  unitsKey,
  rolesKey,
  usersKey,
};

const Map<String, String> _tableByKey = <String, String>{
  productsKey: 'products',
  customersKey: 'customers',
  salesKey: 'sales',
  saleQuotationsKey: 'sale_quotations',
  deliveryNotesKey: 'delivery_notes',
  billsOfMaterialsKey: 'bill_of_materials',
  manufacturingOrdersKey: 'manufacturing_orders',
  suppliersKey: 'suppliers',
  supplierProductPricesKey: 'supplier_product_prices',
  priceListsKey: 'price_lists',
  productPricesKey: 'product_prices',
  productPriceHistoryKey: 'product_price_history',
  productPriceOverridesKey: 'product_price_overrides',
  productCostsKey: 'product_costs',
  costingMethodHistoryKey: 'costing_method_history',
  inventoryCostLayersKey: 'inventory_cost_layers',
  expensesKey: 'expenses',
  purchasesKey: 'purchases',
  inventoryCountsKey: 'inventory_counts',
  warehousesKey: 'warehouses',
  warehouseTransferOrdersKey: 'warehouse_transfer_orders',
  stockMovementsKey: 'stock_movements',
  accountTransactionsKey: 'account_transactions',
  categoriesKey: 'catalog_categories',
  brandsKey: 'catalog_brands',
  unitsKey: 'catalog_units',
  rolesKey: 'user_roles',
  usersKey: 'app_users',
};

const Map<String, String> _entityTypeByKey = <String, String>{
  productsKey: 'product',
  customersKey: 'customer',
  salesKey: 'sale',
  saleQuotationsKey: 'sale_quotation',
  deliveryNotesKey: 'delivery_note',
  billsOfMaterialsKey: 'bill_of_materials',
  manufacturingOrdersKey: 'manufacturing_order',
  suppliersKey: 'supplier',
  supplierProductPricesKey: 'supplierProductPrice',
  priceListsKey: 'priceList',
  productPricesKey: 'productPrice',
  productPriceHistoryKey: 'productPriceHistory',
  productPriceOverridesKey: 'productPriceOverride',
  productCostsKey: 'productCost',
  costingMethodHistoryKey: 'costingMethodHistory',
  inventoryCostLayersKey: 'inventoryCostLayer',
  expensesKey: 'expense',
  purchasesKey: 'purchase',
  inventoryCountsKey: 'inventory_count',
  warehousesKey: 'warehouse',
  warehouseTransferOrdersKey: 'warehouse_transfer_order',
  stockMovementsKey: 'stockMovement',
  accountTransactionsKey: 'accountTransaction',
  categoriesKey: 'category',
  brandsKey: 'brand',
  unitsKey: 'unit',
  rolesKey: 'role',
  usersKey: 'user',
};

const String _saleTotalsCte = '''
      WITH sale_totals AS (
        SELECT s.id, s.invoice_no, s.customer_name, s.document_date,
               s.discount, s.transaction_amount,
               COALESCE(SUM(si.unit_price * si.quantity), 0) AS line_total,
               COALESCE(SUM((si.unit_price - si.unit_cost) * si.quantity), 0)
                 AS line_profit
        FROM sales s
        LEFT JOIN sale_items si ON si.sale_id = s.id
        WHERE s.deleted_at = ''
          AND lower(s.status) NOT IN ('cancelled', 'returned')
        GROUP BY s.id
      )
    ''';

const String _purchaseTotalsCte = '''
      WITH purchase_totals AS (
        SELECT p.id, p.purchase_no, p.supplier_name, p.document_date, p.status,
                p.document_type,
                CASE WHEN p.document_type = 'purchase_return'
                     THEN -COALESCE(SUM(pi.quantity * pi.unit_cost), 0)
                     ELSE COALESCE(SUM(pi.quantity * pi.unit_cost), 0)
                END AS subtotal
        FROM purchases p
        LEFT JOIN purchase_items pi ON pi.purchase_id = p.id
        WHERE p.deleted_at = ''
          AND lower(p.status) NOT IN ('cancelled', 'returned')
        GROUP BY p.id
      )
    ''';

const String _dashboardSaleAmountSql =
    "CASE WHEN transaction_amount > 0 THEN transaction_amount ELSE max(line_total - discount, 0) END";

const String _saleProfitSql = '(line_profit - discount)';
