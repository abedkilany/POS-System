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
import '../../../models/user_role.dart';
import '../../../models/supplier.dart';
import '../../../models/supplier_product_price.dart';
import '../../../models/stock_movement.dart';
import '../../../models/warehouse.dart';
import '../../../models/app_user.dart';
import 'sync_sqlite_store.dart';
import 'ventio_drift_database.dart';

/// SQLite-backed store for Ventio business and settings data.
///
/// Phase 3B stores the main business entities in dedicated SQLite tables
/// instead of keeping everything as one generic JSON key/value table. The
/// public LocalDatabaseService API is intentionally kept stable so the rest of
/// the app can continue using the existing model serializers while the local
/// persistence layer becomes SQLite/Drift authoritative.
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
  static const String productPriceOverridesKey = 'product_price_overrides_v1';
  static const String productCostsKey = 'product_costs_v1';
  static const String costingMethodHistoryKey = 'costing_method_history_v1';
  static const String inventoryCostLayersKey = 'inventory_cost_layers_v1';
  static const String expensesKey = 'expenses_v4';
  static const String purchasesKey = 'purchases_v1';
  static const String inventoryCountsKey = 'inventory_counts_v1';
  static const String warehousesKey = 'warehouses_v1';
  static const String stockMovementsKey = 'stock_movements_v1';
  static const String accountTransactionsKey = 'account_transactions_v1';
  static const String categoriesKey = 'product_categories_v1';
  static const String brandsKey = 'product_brands_v1';
  static const String unitsKey = 'product_units_v1';
  static const String rolesKey = 'roles_v1';
  static const String usersKey = 'users_v1';

  static const Set<String> _entityListKeys = <String>{
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
    productPriceOverridesKey,
    productCostsKey,
    costingMethodHistoryKey,
    inventoryCostLayersKey,
    expensesKey,
    purchasesKey,
    inventoryCountsKey,
    warehousesKey,
    stockMovementsKey,
    accountTransactionsKey,
    categoriesKey,
    brandsKey,
    unitsKey,
    rolesKey,
    usersKey,
  };

  static const Map<String, String> _tableByKey = <String, String>{
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
    productPriceOverridesKey: 'product_price_overrides',
    productCostsKey: 'product_costs',
    costingMethodHistoryKey: 'costing_method_history',
    inventoryCostLayersKey: 'inventory_cost_layers',
    expensesKey: 'expenses',
    purchasesKey: 'purchases',
    inventoryCountsKey: 'inventory_counts',
    warehousesKey: 'warehouses',
    stockMovementsKey: 'stock_movements',
    accountTransactionsKey: 'account_transactions',
    categoriesKey: 'catalog_categories',
    brandsKey: 'catalog_brands',
    unitsKey: 'catalog_units',
    rolesKey: 'user_roles',
    usersKey: 'app_users',
  };

  static const Map<String, String> _entityTypeByKey = <String, String>{
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
    productPriceOverridesKey: 'productPriceOverride',
    productCostsKey: 'productCost',
    costingMethodHistoryKey: 'costingMethodHistory',
    inventoryCostLayersKey: 'inventoryCostLayer',
    expensesKey: 'expense',
    purchasesKey: 'purchase',
    inventoryCountsKey: 'inventory_count',
    warehousesKey: 'warehouse',
    stockMovementsKey: 'stockMovement',
    accountTransactionsKey: 'accountTransaction',
    categoriesKey: 'category',
    brandsKey: 'brand',
    unitsKey: 'unit',
    rolesKey: 'role',
    usersKey: 'user',
  };

  static bool isBusinessKey(String key) {
    if (SyncSqliteStore.isSqliteBackedKey(key)) return false;
    if (key.startsWith('sqlite_phase')) return false;
    return true;
  }

  static bool isTypedEntityKey(String key) => _entityListKeys.contains(key);

  static List<String> get adminEntityKeys =>
      List<String>.unmodifiable(_entityListKeys);

  static Future<void> migrateFromLegacyJsonIfNeeded(
    VentioDriftDatabase db, {
    required Map<String, String> legacyEntries,
  }) async {
    final typedDone = await _metaValue(db, phase3TypedTablesMetaKey) == 'true';
    if (typedDone) return;

    for (final entry in legacyEntries.entries) {
      if (!isBusinessKey(entry.key)) continue;
      await saveKeyJson(db, entry.key, entry.value);
    }
    await _setMeta(db, phase3MigratedMetaKey, 'true');
    await _setMeta(db, phase3TypedTablesMetaKey, 'true');
  }

  static Future<void> markFreshInstallValidated(VentioDriftDatabase db) async {
    await _setMeta(db, phase3MigratedMetaKey, 'true');
    await _setMeta(db, phase3TypedTablesMetaKey, 'true');
    await _setMeta(db, phase3ValidatedMetaKey, 'true');
  }

  static Future<void> migrateComplexTablesFromPayloadJson(
    VentioDriftDatabase db,
  ) async {
    if (await _metaValue(db, phase3ComplexTablesMetaKey) == 'true') return;
    final needsMigration = await _tableHasColumn(
          db, _tableByKey[productsKey]!, 'payload_json') ||
        await _tableHasColumn(db, _tableByKey[salesKey]!, 'payload_json') ||
        await _tableHasColumn(
          db,
          _tableByKey[saleQuotationsKey]!,
          'payload_json',
        ) ||
        await _tableHasColumn(
          db,
          _tableByKey[deliveryNotesKey]!,
          'payload_json',
        ) ||
        await _tableHasColumn(db, _tableByKey[purchasesKey]!, 'payload_json') ||
        await _tableHasColumn(
          db,
          _tableByKey[inventoryCountsKey]!,
          'payload_json',
        ) ||
        await _tableHasColumn(
          db,
          _tableByKey[billsOfMaterialsKey]!,
          'payload_json',
        ) ||
        await _tableHasColumn(
          db,
          _tableByKey[manufacturingOrdersKey]!,
          'payload_json',
        );
    if (!needsMigration) {
      await _setMeta(db, phase3ComplexTablesMetaKey, 'true');
      return;
    }
    await _migrateComplexTables(db);
    await _setMeta(db, phase3ComplexTablesMetaKey, 'true');
  }

  static Future<bool> isValidationPassed(VentioDriftDatabase db) async {
    return await _metaValue(db, phase3ValidatedMetaKey) == 'true';
  }

  static Future<Map<String, String>> hydrateKeyMirror(
      VentioDriftDatabase db) async {
    final mirror = await hydrateScalarKeyMirror(db);

    for (final entry in _tableByKey.entries) {
      mirror[entry.key] = await readEntityListJsonByKey(db, entry.key) ?? '[]';
    }

    return mirror;
  }

  /// Startup-fast mirror hydration.
  ///
  /// Phase 3 used to rebuild JSON strings for every typed table during
  /// LocalDatabaseService.initialize(), then AppStore decoded the same JSON
  /// again immediately after. With large datasets this made app launch pay for
  /// products/sales/stock/accounting even before the user opened a page.
  ///
  /// Keep only scalar/settings keys in the startup mirror. Typed entity lists
  /// are loaded by AppStore in two stages: small catalog/login-critical lists
  /// during initialize(), and large transactional lists shortly after startup.
  static Future<Map<String, String>> hydrateScalarKeyMirror(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT key, value
      FROM local_key_values
      ORDER BY key ASC
    ''').get();
    final mirror = <String, String>{
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };

    for (final key in _entityListKeys) {
      mirror.remove(key);
    }

    // These lists are small and needed for login/catalog initialization. Keep
    // them available synchronously to AppStore without loading transactional
    // tables such as sales, purchases, stock movements, and accounting ledger.
    for (final key in <String>{
      categoriesKey,
      brandsKey,
      unitsKey,
      rolesKey,
      usersKey
    }) {
      mirror[key] = await readEntityListJsonByKey(db, key) ?? '[]';
    }

    final settingsRows = await db.customSelect('''
      SELECT key, value
      FROM settings
      ORDER BY key ASC
    ''').get();
    for (final row in settingsRows) {
      mirror[row.read<String>('key')] = row.read<String>('value');
    }
    return mirror;
  }

  static Future<String?> readEntityListJsonByKey(
      VentioDriftDatabase db, String key) async {
    final table = _tableByKey[key];
    if (table == null) return null;
    final payloads = await _readEntityListPayloadsByKey(db, key);
    return jsonEncode(payloads);
  }

  static Future<List<String>> readEntityListJsonBatches(
    VentioDriftDatabase db,
    String key, {
    int batchSize = 100,
  }) async {
    final table = _tableByKey[key];
    if (table == null) return const <String>[];
    final size = batchSize.clamp(1, 1000).toInt();
    final payloads = await _readEntityListPayloadsByKey(db, key);
    final batches = <String>[];
    for (var index = 0; index < payloads.length; index += size) {
      final end = (index + size < payloads.length)
          ? index + size
          : payloads.length;
      batches.add(jsonEncode(payloads.sublist(index, end)));
    }
    return batches;
  }

  static Future<List<Map<String, dynamic>>> _readEntityListPayloadsByKey(
    VentioDriftDatabase db,
    String key,
  ) async {
    switch (key) {
      case productsKey:
        return (await readProducts(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case customersKey:
        return (await readCustomers(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case suppliersKey:
        return (await readSuppliers(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case salesKey:
        return (await readSales(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case saleQuotationsKey:
        return (await readSaleQuotations(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case deliveryNotesKey:
        return (await readDeliveryNotes(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case billsOfMaterialsKey:
        return (await readBillOfMaterials(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case manufacturingOrdersKey:
        return (await readManufacturingOrders(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case inventoryCountsKey:
        return (await readInventoryCounts(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case warehousesKey:
        return (await readWarehouses(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case stockMovementsKey:
        return (await readStockMovements(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case accountTransactionsKey:
        return (await readAccountTransactions(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case categoriesKey:
        return (await readCatalogItems(db, _tableByKey[categoriesKey]!))
            .map((item) => item.toJson())
            .toList(growable: false);
      case brandsKey:
        return (await readCatalogItems(db, _tableByKey[brandsKey]!))
            .map((item) => item.toJson())
            .toList(growable: false);
      case unitsKey:
        return (await readCatalogItems(db, _tableByKey[unitsKey]!))
            .map((item) => item.toJson())
            .toList(growable: false);
      case priceListsKey:
        return (await readPriceLists(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case productPricesKey:
        return (await readProductPrices(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case productPriceOverridesKey:
        return (await readProductPriceOverrides(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case productCostsKey:
        return (await readProductCosts(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case costingMethodHistoryKey:
        return (await readCostingMethodHistory(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case inventoryCostLayersKey:
        return (await readInventoryCostLayers(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case supplierProductPricesKey:
        return (await readSupplierProductPrices(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case rolesKey:
        return (await readRoles(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      case usersKey:
        return (await readUsers(db))
            .map((item) => item.toJson())
            .toList(growable: false);
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  static Future<List<StockMovement>> readStockMovements(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, product_id, product_name, movement_type, quantity,
             movement_date, reference_id, reference_no, reason,
             adjustment_category, notes, evidence_ref, warehouse_id,
             warehouse_name, unit_cost, created_at, updated_at, device_id,
             sync_status, store_id, branch_id, version,
             last_modified_by_device_id, reviewed_at, reviewed_by, review_note
      FROM stock_movements
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map(_stockMovementFromRow).toList(growable: false);
  }

  static Future<List<AccountTransaction>> readAccountTransactions(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, account_type, account_id, account_name, transaction_date,
             transaction_type, reference_id, reference_no, debit, credit,
             currency, payment_method, note, created_at, updated_at,
             deleted_at, device_id, sync_status, store_id, branch_id,
             version, last_modified_by_device_id
      FROM account_transactions
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map(_accountTransactionFromRow).toList(growable: false);
  }

  static Future<List<Customer>> readCustomers(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name, phone, address, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM customers
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => Customer.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<Supplier>> readSuppliers(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name, name_en AS nameEn, name_ar AS nameAr, phone, address,
             notes, created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM suppliers
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<Expense>> readExpenses(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, title, category, amount, original_amount AS originalAmount,
             original_currency AS originalCurrency,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             expense_date AS date, notes, expense_status AS status,
             cancel_reason AS cancelReason,
             cancelled_by_device_id AS cancelledByDeviceId,
             cancelled_at AS cancelledAt, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM expenses
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => Expense.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<Warehouse>> readWarehouses(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name, code, location,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouses
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      return Warehouse.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<CatalogItem>> readCatalogItems(
    VentioDriftDatabase db,
    String table,
  ) async {
    final rows = await db.customSelect('''
      SELECT id, name_en AS nameEn, name_ar AS nameAr, code,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM $table
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => CatalogItem.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<UserRole>> readRoles(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name, permissions_json AS permissionsJson,
             CASE WHEN is_system = 1 THEN 1 ELSE 0 END AS isSystem,
             created_at AS createdAt, updated_at AS updatedAt
      FROM user_roles
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      final permissionsJson = (data['permissionsJson']?.toString() ?? '').trim();
      data['permissions'] = permissionsJson.isEmpty
          ? const <String>[]
          : (jsonDecode(permissionsJson) as List<dynamic>)
              .map((item) => item.toString())
              .toList(growable: false);
      data['isSystem'] = data['isSystem'] == 1 || data['isSystem'] == true;
      data.remove('permissionsJson');
      return UserRole.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<AppUser>> readUsers(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, full_name AS fullName, username, password_hash AS passwordHash,
             role_id AS roleId, extra_permissions_json AS extraPermissionsJson,
             denied_permissions_json AS deniedPermissionsJson,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             CASE WHEN is_system = 1 THEN 1 ELSE 0 END AS isSystem,
             created_at AS createdAt, updated_at AS updatedAt,
             last_login_at AS lastLoginAt
      FROM app_users
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      final extraPermissionsJson =
          (data['extraPermissionsJson']?.toString() ?? '').trim();
      final deniedPermissionsJson =
          (data['deniedPermissionsJson']?.toString() ?? '').trim();
      data['extraPermissions'] = extraPermissionsJson.isEmpty
          ? const <String>[]
          : (jsonDecode(extraPermissionsJson) as List<dynamic>)
              .map((item) => item.toString())
              .toList(growable: false);
      data['deniedPermissions'] = deniedPermissionsJson.isEmpty
          ? const <String>[]
          : (jsonDecode(deniedPermissionsJson) as List<dynamic>)
              .map((item) => item.toString())
              .toList(growable: false);
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      data['isSystem'] = data['isSystem'] == 1 || data['isSystem'] == true;
      data.remove('extraPermissionsJson');
      data.remove('deniedPermissionsJson');
      return AppUser.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<PriceList>> readPriceLists(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, name, code, CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt
      FROM price_lists
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      return PriceList.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<ProductPrice>> readProductPrices(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, product_id AS productId, price_list_id AS priceListId,
             unit_id AS unitId, base_currency_code AS baseCurrencyCode,
             base_amount AS baseAmount,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt
      FROM product_prices
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      return ProductPrice.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<ProductPriceOverride>> readProductPriceOverrides(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, product_price_id AS productPriceId, currency_code AS currencyCode,
             amount, mode, CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt
      FROM product_price_overrides
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      return ProductPriceOverride.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<ProductCost>> readProductCosts(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT product_id AS productId, average_cost AS averageCost,
             last_cost AS lastCost, currency_code AS currencyCode,
             created_at AS createdAt, updated_at AS updatedAt
      FROM product_costs
      ORDER BY updated_at ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => ProductCost.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<CostingMethodHistory>> readCostingMethodHistory(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, method, effective_from AS effectiveFrom,
             effective_to AS effectiveTo, reason, created_at AS createdAt,
             updated_at AS updatedAt
      FROM costing_method_history
      ORDER BY updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) =>
            CostingMethodHistory.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<List<InventoryCostLayer>> readInventoryCostLayers(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, product_id AS productId, product_name AS productName,
             quantity_received AS quantityReceived,
             quantity_remaining AS quantityRemaining, unit_cost AS unitCost,
             currency_code AS currencyCode, exchange_rate AS exchangeRate,
             purchase_id AS purchaseId, purchase_item_id AS purchaseItemId,
             source_type AS sourceType, source_id AS sourceId,
             CASE WHEN is_closed = 1 THEN 1 ELSE 0 END AS isClosed,
             created_at AS createdAt, updated_at AS updatedAt
      FROM inventory_cost_layers
      ORDER BY updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isClosed'] = data['isClosed'] == 1 || data['isClosed'] == true;
      return InventoryCostLayer.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<SupplierProductPrice>> readSupplierProductPrices(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, product_id AS productId, supplier_id AS supplierId, cost,
             currency, CASE WHEN is_preferred = 1 THEN 1 ELSE 0 END AS isPreferred,
             supplier_sku AS supplierSku, min_order_qty AS minOrderQty,
             lead_time_days AS leadTimeDays, notes, price_history_json AS priceHistoryJson,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM supplier_product_prices
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isPreferred'] =
          data['isPreferred'] == 1 || data['isPreferred'] == true;
      final historyJson = (data['priceHistoryJson']?.toString() ?? '').trim();
      data['priceHistory'] = historyJson.isEmpty
          ? const <Map<String, dynamic>>[]
          : (jsonDecode(historyJson) as List<dynamic>)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
      data.remove('priceHistoryJson');
      return SupplierProductPrice.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<Product>> readProducts(VentioDriftDatabase db) async {
    final productRows = await db.customSelect('''
      SELECT id, name, code, name_en AS nameEn, name_ar AS nameAr,
             price, cost, original_cost AS originalCost,
             cost_currency AS costCurrency, usd_cost AS usdCost,
             cost_exchange_rate_at_entry AS costExchangeRateAtEntry,
             original_price AS originalPrice,
             original_currency AS originalCurrency,
             usd_price AS usdPrice,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             stock, category, barcode, brand, supplier, description, unit,
             quantity_type AS quantityType,
             low_stock_threshold AS lowStockThreshold,
             CASE WHEN track_stock = 1 THEN 1 ELSE 0 END AS trackStock,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             image_path AS imagePath, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM products
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final saleUnitRows = await db.customSelect('''
      SELECT product_id AS productId, line_no AS lineNo, unit_id AS id,
             name, conversion_to_base AS conversionToBase,
             price, original_price AS originalPrice,
             original_currency AS originalCurrency, barcode,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault
      FROM product_sale_units
      ORDER BY product_id ASC, line_no ASC
    ''').get();
    final purchaseUnitRows = await db.customSelect('''
      SELECT product_id AS productId, line_no AS lineNo, unit_id AS id,
             name, conversion_to_base AS conversionToBase,
             price, original_price AS originalPrice,
             original_currency AS originalCurrency, barcode,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault
      FROM product_purchase_units
      ORDER BY product_id ASC, line_no ASC
    ''').get();

    final saleUnitsByProduct = <String, List<Map<String, dynamic>>>{};
    for (final row in saleUnitRows) {
      final data = Map<String, dynamic>.from(row.data);
      final productId = data['productId']?.toString() ?? '';
      if (productId.isEmpty) continue;
      data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
      saleUnitsByProduct.putIfAbsent(
        productId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    final purchaseUnitsByProduct = <String, List<Map<String, dynamic>>>{};
    for (final row in purchaseUnitRows) {
      final data = Map<String, dynamic>.from(row.data);
      final productId = data['productId']?.toString() ?? '';
      if (productId.isEmpty) continue;
      data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
      purchaseUnitsByProduct.putIfAbsent(
        productId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    return productRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['trackStock'] = data['trackStock'] == 1 || data['trackStock'] == true;
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      data['saleUnits'] = saleUnitsByProduct[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      data['purchaseUnits'] =
          purchaseUnitsByProduct[data['id']?.toString() ?? ''] ??
              const <Map<String, dynamic>>[];
      return Product.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<Sale>> readSales(VentioDriftDatabase db) async {
    final saleRows = await db.customSelect('''
      SELECT id, invoice_no AS invoiceNo, customer_name AS customerName,
             customer_id AS customerId, document_date AS date,
             status, discount, original_discount AS originalDiscount,
             discount_currency AS discountCurrency,
             discount_exchange_rate_at_entry AS discountExchangeRateAtEntry,
             payment_method AS paymentMethod,
             payment_status AS paymentStatus,
             invoice_currency AS invoiceCurrency,
             payment_currency AS paymentCurrency,
             exchange_rate_at_payment AS exchangeRateAtPayment,
             base_currency AS baseCurrency,
             exchange_rate_at_invoice AS exchangeRateAtInvoice,
             transaction_amount AS transactionAmount,
             base_amount AS baseAmount,
             paid_base_amount AS paidBaseAmount,
             exchange_difference_amount AS exchangeDifferenceAmount,
             paid_amount AS paidAmount,
             cash_received_amount AS cashReceivedAmount,
             paid_amount_in_payment_currency AS paidAmountInPaymentCurrency,
             cash_received_amount_in_payment_currency
               AS cashReceivedAmountInPaymentCurrency,
             note, created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM sales
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final itemRows = await db.customSelect('''
      SELECT id, sale_id AS saleId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM sale_items
      ORDER BY sale_id ASC, line_no ASC
    ''').get();
    final consumptionRows = await db.customSelect('''
      SELECT id, sale_item_id AS saleItemId, line_no AS lineNo,
             layer_id AS layerId, quantity, unit_cost AS unitCost,
             currency_code AS currencyCode
      FROM sale_item_cost_layer_consumptions
      ORDER BY sale_item_id ASC, line_no ASC
    ''').get();

    final consumptionsByItem = <String, List<Map<String, dynamic>>>{};
    for (final row in consumptionRows) {
      final data = Map<String, dynamic>.from(row.data);
      final saleItemId = data['saleItemId']?.toString() ?? '';
      if (saleItemId.isEmpty) continue;
      consumptionsByItem.putIfAbsent(
        saleItemId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    final itemsBySale = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final data = Map<String, dynamic>.from(row.data);
      final saleId = data['saleId']?.toString() ?? '';
      if (saleId.isEmpty) continue;
      final itemId = data['id']?.toString() ?? '';
      data['costLayerConsumptions'] =
          consumptionsByItem[itemId] ?? const <Map<String, dynamic>>[];
      itemsBySale.putIfAbsent(saleId, () => <Map<String, dynamic>>[]).add(data);
    }

    return saleRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['items'] = itemsBySale[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return Sale.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<SaleQuotation>> readSaleQuotations(
      VentioDriftDatabase db) async {
    final quotationRows = await db.customSelect('''
      SELECT id, quotation_no AS quotationNo,
             customer_name AS customerName,
             customer_id AS customerId,
             document_date AS date,
             valid_until AS validUntil,
             status, discount, invoice_currency AS invoiceCurrency,
             note, converted_sale_id AS convertedSaleId,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM sale_quotations
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final itemRows = await db.customSelect('''
      SELECT id, sale_quotation_id AS saleQuotationId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM sale_quotation_items
      ORDER BY sale_quotation_id ASC, line_no ASC
    ''').get();
    final itemsByQuotation = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final data = Map<String, dynamic>.from(row.data);
      final quotationId = data['saleQuotationId']?.toString() ?? '';
      if (quotationId.isEmpty) continue;
      itemsByQuotation.putIfAbsent(
        quotationId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    return quotationRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['items'] = itemsByQuotation[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return SaleQuotation.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<DeliveryNote>> readDeliveryNotes(
      VentioDriftDatabase db) async {
    final deliveryRows = await db.customSelect('''
      SELECT id, delivery_no AS deliveryNo,
             sale_id AS saleId,
             invoice_no AS invoiceNo,
             customer_name AS customerName,
             customer_id AS customerId,
             document_date AS date,
             status, note, delivered_at AS deliveredAt,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM delivery_notes
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final itemRows = await db.customSelect('''
      SELECT id, delivery_note_id AS deliveryNoteId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM delivery_note_items
      ORDER BY delivery_note_id ASC, line_no ASC
    ''').get();
    final itemsByDelivery = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final data = Map<String, dynamic>.from(row.data);
      final deliveryId = data['deliveryNoteId']?.toString() ?? '';
      if (deliveryId.isEmpty) continue;
      itemsByDelivery.putIfAbsent(
        deliveryId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    return deliveryRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['items'] = itemsByDelivery[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return DeliveryNote.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<Purchase>> readPurchases(VentioDriftDatabase db) async {
    final purchaseRows = await db.customSelect('''
      SELECT id, purchase_no AS purchaseNo,
             supplier_id AS supplierId,
             supplier_name AS supplierName,
             document_date AS date,
             status, note, payment_status AS paymentStatus,
             payment_method AS paymentMethod,
             paid_amount AS paidAmount,
             cancel_reason AS cancelReason,
             cancelled_by_device_id AS cancelledByDeviceId,
             CASE WHEN reversal_applied = 1 THEN 1 ELSE 0 END AS reversalApplied,
             cancelled_at AS cancelledAt,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM purchases
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final itemRows = await db.customSelect('''
      SELECT id, purchase_id AS purchaseId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             quantity, unit_cost AS unitCost,
             purchase_unit_id AS purchaseUnitId,
             purchase_unit_name AS purchaseUnitName,
             conversion_to_base AS conversionToBase,
             original_unit_cost AS originalUnitCost,
             unit_cost_currency AS unitCostCurrency,
             exchange_rate_at_entry AS exchangeRateAtEntry
      FROM purchase_items
      ORDER BY purchase_id ASC, line_no ASC
    ''').get();
    final itemsByPurchase = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final data = Map<String, dynamic>.from(row.data);
      final purchaseId = data['purchaseId']?.toString() ?? '';
      if (purchaseId.isEmpty) continue;
      itemsByPurchase.putIfAbsent(
        purchaseId,
        () => <Map<String, dynamic>>[],
      ).add(data);
    }

    return purchaseRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['reversalApplied'] =
          data['reversalApplied'] == 1 || data['reversalApplied'] == true;
      data['items'] = itemsByPurchase[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return Purchase.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<InventoryCountSession>> readInventoryCounts(
      VentioDriftDatabase db) async {
    final sessionRows = await db.customSelect('''
      SELECT id, count_no AS countNo, created_at AS createdAt,
             created_by AS createdBy, warehouse_id AS warehouseId,
             warehouse_name AS warehouseName, status, notes,
             approved_at AS approvedAt, approved_by AS approvedBy,
             updated_at AS updatedAt
      FROM inventory_counts
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final lineRows = await db.customSelect('''
      SELECT id, inventory_count_id AS inventoryCountId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             product_code AS productCode, snapshot_stock AS snapshotStock,
             counted_qty AS countedQty, counted_at AS countedAt,
             counted_by AS countedBy, note
      FROM inventory_count_lines
      ORDER BY inventory_count_id ASC, line_no ASC
    ''').get();
    final linesByCount = <String, List<Map<String, dynamic>>>{};
    for (final row in lineRows) {
      final data = Map<String, dynamic>.from(row.data);
      final countId = data['inventoryCountId']?.toString() ?? '';
      if (countId.isEmpty) continue;
      linesByCount.putIfAbsent(countId, () => <Map<String, dynamic>>[]).add(data);
    }

    return sessionRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['lines'] = linesByCount[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return InventoryCountSession.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<BillOfMaterials>> readBillOfMaterials(
      VentioDriftDatabase db) async {
    final bomRows = await db.customSelect('''
      SELECT id, name, output_product_id AS outputProductId,
             output_product_name AS outputProductName,
             output_quantity AS outputQuantity,
             notes, CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM bill_of_materials
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final lineRows = await db.customSelect('''
      SELECT id, bill_of_material_id AS billOfMaterialId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             quantity, unit_cost AS unitCost
      FROM bill_of_materials_lines
      ORDER BY bill_of_material_id ASC, line_no ASC
    ''').get();
    final linesByBom = <String, List<Map<String, dynamic>>>{};
    for (final row in lineRows) {
      final data = Map<String, dynamic>.from(row.data);
      final bomId = data['billOfMaterialId']?.toString() ?? '';
      if (bomId.isEmpty) continue;
      linesByBom.putIfAbsent(bomId, () => <Map<String, dynamic>>[]).add(data);
    }

    return bomRows.map((row) {
      final data = Map<String, dynamic>.from(row.data);
      data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
      data['components'] = linesByBom[data['id']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      return BillOfMaterials.fromJson(data);
    }).toList(growable: false);
  }

  static Future<List<ManufacturingOrder>> readManufacturingOrders(
      VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT id, order_no AS orderNo, bom_id AS bomId, bom_name AS bomName,
             output_product_id AS outputProductId,
             output_product_name AS outputProductName,
             quantity, status, notes,
             document_date AS date, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM manufacturing_orders
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => ManufacturingOrder.fromJson(
              Map<String, dynamic>.from(row.data),
            ))
        .toList(growable: false);
  }

  static Future<void> saveKeyJson(
      VentioDriftDatabase db, String key, String value) async {
    if (isTypedEntityKey(key)) {
      // Performance fix: normal app saves must be incremental. The old Phase 3B
      // compatibility path deleted the whole entity table and re-inserted every
      // row on every product/customer/sale change, which preserved legacy JSON storage's slow
      // "rewrite the whole list" behavior inside SQLite. Keep local_key_values
      // out of the hot path as well; hydrateKeyMirror rebuilds the JSON mirror
      // from the typed tables on startup.
      await _mergeEntityList(db, key, value);
      return;
    }

    // Settings and scalar app state get their own typed table. local_key_values
    // remains as a compatibility mirror for older diagnostics/exports.
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
    await _saveLocalMirrorValue(db, key, value);
  }

  static Future<void> upsertEntityPayload(
    VentioDriftDatabase db,
    String key,
    Map<String, dynamic> payload, {
    int? sortIndex,
  }) async {
    await upsertEntityPayloads(
      db,
      key,
      <Map<String, dynamic>>[payload],
      sortIndices: <int?>[sortIndex],
    );
  }

  static Future<void> upsertEntityPayloads(
    VentioDriftDatabase db,
    String key,
    List<Map<String, dynamic>> payloads, {
    List<int?>? sortIndices,
  }) async {
    final table = _tableByKey[key];
    final entityType = _entityTypeByKey[key];
    if (table == null || entityType == null) {
      throw ArgumentError('Key $key is not a typed SQLite entity key.');
    }
    await db.transaction(() async {
      for (var index = 0; index < payloads.length; index += 1) {
        final payload = payloads[index];
        final sortIndex = sortIndices != null && index < sortIndices.length
            ? sortIndices[index]
            : null;
        final now = DateTime.now().toUtc().toIso8601String();
        final id = (payload['id']?.toString().isNotEmpty ?? false)
            ? payload['id'].toString()
            : '${entityType}_${now.hashCode}';
        final payloadJson = jsonEncode(payload);
        final createdAt = _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            now;
        final updatedAt = _dateString(payload['updatedAt']) ?? createdAt;
        final deletedAt = _dateString(payload['deletedAt']) ?? '';
        if (key == stockMovementsKey) {
          await _upsertStockMovementPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == accountTransactionsKey) {
          await _upsertAccountTransactionPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == customersKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'name': _textValue(payload['name']),
              'phone': _textValue(payload['phone']),
              'address': _textValue(payload['address']),
            },
          );
          continue;
        }
        if (key == suppliersKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'name': _textValue(payload['name']),
              'name_en': _textValue(payload['nameEn']),
              'name_ar': _textValue(payload['nameAr']),
              'phone': _textValue(payload['phone']),
              'address': _textValue(payload['address']),
              'notes': _textValue(payload['notes']),
            },
          );
          continue;
        }
        if (key == expensesKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'title': _textValue(payload['title']),
              'category': _textValue(payload['category']),
              'amount': _doubleValue(payload['amount']),
              'original_amount': _doubleValue(
                payload['originalAmount'],
                fallback: _doubleValue(payload['amount']),
              ),
              'original_currency':
                  _textValue(payload['originalCurrency'], fallback: 'USD'),
              'exchange_rate_at_entry':
                  _doubleValue(payload['exchangeRateAtEntry']),
              'expense_date': _dateString(payload['date']) ?? createdAt,
              'notes': _textValue(payload['notes']),
              'expense_status':
                  _textValue(payload['status'], fallback: 'Draft'),
              'cancel_reason': _textValue(payload['cancelReason']),
              'cancelled_by_device_id':
                  _textValue(payload['cancelledByDeviceId']),
              'cancelled_at': _dateString(payload['cancelledAt']) ?? '',
            },
          );
          continue;
        }
        if (key == warehousesKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'name': _textValue(payload['name']),
              'code': _textValue(payload['code']),
              'location': _textValue(payload['location']),
              'is_default': _boolValue(payload['isDefault']),
              'is_active': _boolValue(payload['isActive'], fallback: true),
            },
          );
          continue;
        }
        if (key == categoriesKey || key == brandsKey || key == unitsKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'name_en': _textValue(payload['nameEn']),
              'name_ar': _textValue(payload['nameAr']),
              'code': _textValue(payload['code']),
            },
          );
          continue;
        }
        if (key == rolesKey) {
          await _upsertRolePayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == usersKey) {
          await _upsertUserPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == supplierProductPricesKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'product_id': _textValue(payload['productId']),
              'supplier_id': _textValue(payload['supplierId']),
              'cost': _doubleValue(payload['cost'] ?? payload['unitCost']),
              'currency': _textValue(payload['currency'], fallback: 'USD'),
              'is_preferred': _boolValue(
                payload['isPreferred'] ?? payload['preferredSupplier'],
              ),
              'supplier_sku': _textValue(
                payload['supplierSku'] ??
                    payload['supplierSKU'] ??
                    payload['supplierCode'],
              ),
              'min_order_qty': _doubleValue(
                payload['minOrderQty'] ?? payload['minimumOrderQty'],
              ),
              'lead_time_days': _intValue(
                payload['leadTimeDays'] ?? payload['lead_time_days'],
                fallback: 0,
              ),
              'notes': _textValue(payload['notes']),
              'price_history_json':
                  jsonEncode(payload['priceHistory'] ?? const []),
            },
          );
          continue;
        }
        if (key == priceListsKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'name': _textValue(payload['name']),
              'code': _textValue(payload['code']),
              'is_default': _boolValue(payload['isDefault']),
              'is_active': _boolValue(payload['isActive'], fallback: true),
            },
          );
          continue;
        }
        if (key == productPricesKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'product_id': _textValue(payload['productId']),
              'price_list_id': _textValue(payload['priceListId']),
              'unit_id': _textValue(payload['unitId'], fallback: 'base'),
              'base_currency_code':
                  _textValue(payload['baseCurrencyCode'], fallback: 'USD'),
              'base_amount': _doubleValue(payload['baseAmount']),
              'is_active': _boolValue(payload['isActive'], fallback: true),
            },
          );
          continue;
        }
        if (key == productPriceOverridesKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'product_price_id': _textValue(payload['productPriceId']),
              'currency_code':
                  _textValue(payload['currencyCode'], fallback: 'USD'),
              'amount': _doubleValue(payload['amount']),
              'mode': _textValue(payload['mode'], fallback: 'fixed'),
              'is_active': _boolValue(payload['isActive'], fallback: true),
            },
          );
          continue;
        }
        if (key == productCostsKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'product_id': _textValue(payload['productId']),
              'average_cost': _doubleValue(payload['averageCost']),
              'last_cost': _doubleValue(payload['lastCost']),
              'currency_code':
                  _textValue(payload['currencyCode'], fallback: 'USD'),
            },
          );
          continue;
        }
        if (key == costingMethodHistoryKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'method': _textValue(
                payload['method'],
                fallback: InventoryCostingMethod.weightedAverage.code,
              ),
              'effective_from':
                  _dateString(payload['effectiveFrom']) ?? createdAt,
              'effective_to': _dateString(payload['effectiveTo']) ?? '',
              'reason': _textValue(payload['reason']),
            },
          );
          continue;
        }
        if (key == inventoryCostLayersKey) {
          await _upsertTypedEntityRow(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
            typedColumns: <String, Object?>{
              'product_id': _textValue(payload['productId']),
              'product_name': _textValue(payload['productName']),
              'quantity_received': _doubleValue(payload['quantityReceived']),
              'quantity_remaining': _doubleValue(payload['quantityRemaining']),
              'unit_cost': _doubleValue(payload['unitCost']),
              'currency_code':
                  _textValue(payload['currencyCode'], fallback: 'USD'),
              'exchange_rate':
                  _doubleValue(payload['exchangeRate'], fallback: 1),
              'purchase_id': _textValue(payload['purchaseId']),
              'purchase_item_id': _textValue(payload['purchaseItemId']),
              'source_type':
                  _textValue(payload['sourceType'], fallback: 'purchase'),
              'source_id': _textValue(payload['sourceId']),
              'is_closed': _boolValue(payload['isClosed']),
            },
          );
          continue;
        }
        if (key == productsKey) {
          await _upsertProductPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == salesKey) {
          await _upsertSalePayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == saleQuotationsKey) {
          await _upsertSaleQuotationPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == deliveryNotesKey) {
          await _upsertDeliveryNotePayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == purchasesKey) {
          await _upsertPurchasePayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == inventoryCountsKey) {
          await _upsertInventoryCountPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == billsOfMaterialsKey) {
          await _upsertBillOfMaterialsPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        if (key == manufacturingOrdersKey) {
          await _upsertManufacturingOrderPayload(
            db,
            table,
            entityType,
            payload,
            id: id,
            payloadJson: payloadJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sortIndex: sortIndex ?? 0,
          );
          continue;
        }
        await db.customInsert(
          """
          INSERT OR REPLACE INTO $table
            (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status, store_id, branch_id, version, sort_index)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
          variables: <Variable<Object>>[
            Variable<String>(id),
            Variable<String>(entityType),
            Variable<String>(createdAt),
            Variable<String>(updatedAt),
            Variable<String>(deletedAt),
            Variable<String>(payload['deviceId']?.toString() ?? ''),
            Variable<String>(payload['syncStatus']?.toString() ?? ''),
            Variable<String>(payload['storeId']?.toString() ?? ''),
            Variable<String>(payload['branchId']?.toString() ?? ''),
            Variable<int>(_intValue(payload['version'], fallback: 1)),
            Variable<int>(sortIndex ?? 0),
          ],
        );
      }
    });
  }

  static Future<void> _upsertTypedEntityRow(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
    required Map<String, Object?> typedColumns,
  }) async {
    final columns = <String>[
      'id',
      'entity_type',
      'created_at',
      'updated_at',
      'deleted_at',
      'device_id',
      'sync_status',
      'store_id',
      'branch_id',
      'version',
      'last_modified_by_device_id',
      'sort_index',
      ...typedColumns.keys,
    ];
    final placeholders =
        List<String>.filled(columns.length, '?', growable: false).join(', ');
    final values = <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(entityType),
      Variable<String>(createdAt),
      Variable<String>(updatedAt),
      Variable<String>(deletedAt),
      Variable<String>(_textValue(payload['deviceId'])),
      Variable<String>(_textValue(payload['syncStatus'])),
      Variable<String>(_textValue(payload['storeId'])),
      Variable<String>(_textValue(payload['branchId'])),
      Variable<int>(_intValue(payload['version'], fallback: 1)),
      Variable<String>(
        _textValue(payload['lastModifiedByDeviceId'] ?? payload['deviceId']),
      ),
      Variable<int>(sortIndex),
      for (final value in typedColumns.values)
        Variable<Object>(_sqlValue(value)),
    ];

    await db.customInsert(
      'INSERT OR REPLACE INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      variables: values,
    );
  }

  static Future<void> _upsertStockMovementPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await db.customInsert(
      """
      INSERT OR REPLACE INTO $table
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         product_id, product_name, movement_type, quantity, movement_date,
         reference_id, reference_no, reason, adjustment_category, notes,
         evidence_ref, warehouse_id, warehouse_name, unit_cost,
         last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(entityType),
        Variable<String>(createdAt),
        Variable<String>(updatedAt),
        Variable<String>(deletedAt),
        Variable<String>(_textValue(payload['deviceId'])),
        Variable<String>(_textValue(payload['syncStatus'])),
        Variable<String>(_textValue(payload['storeId'])),
        Variable<String>(_textValue(payload['branchId'])),
        Variable<int>(_intValue(payload['version'], fallback: 1)),
        Variable<int>(sortIndex),
        Variable<String>(_textValue(payload['productId'])),
        Variable<String>(_textValue(payload['productName'])),
        Variable<String>(_textValue(payload['type'], fallback: 'adjustment')),
        Variable<double>(_doubleValue(payload['quantity'])),
        Variable<String>(
          _dateString(payload['date']) ??
              _dateString(payload['createdAt']) ??
              createdAt,
        ),
        Variable<String>(
          _textValue(
            payload['referenceId'] ??
                payload['saleId'] ??
                payload['purchaseId'],
          ),
        ),
        Variable<String>(_textValue(payload['referenceNo'])),
        Variable<String>(_textValue(payload['reason'])),
        Variable<String>(
          _textValue(
            payload['adjustmentCategory'] ?? payload['category'],
          ),
        ),
        Variable<String>(_textValue(payload['notes'])),
        Variable<String>(_textValue(payload['evidenceRef'])),
        Variable<String>(_textValue(payload['warehouseId'], fallback: 'main')),
        Variable<String>(
          _textValue(payload['warehouseName'], fallback: 'Main warehouse'),
        ),
        Variable<double>(_doubleValue(payload['unitCost'])),
        Variable<String>(
          _textValue(
            payload['lastModifiedByDeviceId'] ?? payload['deviceId'],
          ),
        ),
        Variable<String>(_dateString(payload['reviewedAt']) ?? ''),
        Variable<String>(_textValue(payload['reviewedBy'])),
        Variable<String>(_textValue(payload['reviewNote'])),
      ],
    );
  }

  static Future<void> _upsertAccountTransactionPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await db.customInsert(
      """
      INSERT OR REPLACE INTO $table
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(entityType),
        Variable<String>(createdAt),
        Variable<String>(updatedAt),
        Variable<String>(deletedAt),
        Variable<String>(_textValue(payload['deviceId'])),
        Variable<String>(_textValue(payload['syncStatus'])),
        Variable<String>(_textValue(payload['storeId'])),
        Variable<String>(_textValue(payload['branchId'])),
        Variable<int>(_intValue(payload['version'], fallback: 1)),
        Variable<int>(sortIndex),
        Variable<String>(_textValue(payload['accountType'])),
        Variable<String>(_textValue(payload['accountId'])),
        Variable<String>(_textValue(payload['accountName'])),
        Variable<String>(
          _dateString(payload['date']) ??
              _dateString(payload['createdAt']) ??
              createdAt,
        ),
        Variable<String>(_textValue(payload['type'])),
        Variable<String>(_textValue(payload['referenceId'])),
        Variable<String>(_textValue(payload['referenceNo'])),
        Variable<double>(_doubleValue(payload['debit'])),
        Variable<double>(_doubleValue(payload['credit'])),
        Variable<String>(_textValue(payload['currency'], fallback: 'USD')),
        Variable<String>(_textValue(payload['paymentMethod'])),
        Variable<String>(_textValue(payload['note'])),
        Variable<String>(
          _textValue(
            payload['lastModifiedByDeviceId'] ?? payload['deviceId'],
          ),
        ),
      ],
    );
  }

  static Future<void> _upsertProductPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'name': _textValue(payload['name']),
        'code': _textValue(payload['code']),
        'name_en': _textValue(payload['nameEn']),
        'name_ar': _textValue(payload['nameAr']),
        'price': _doubleValue(payload['price'] ?? payload['usdPrice']),
        'cost': _doubleValue(payload['cost'] ?? payload['usdCost']),
        'original_cost': _doubleValue(
          payload['originalCost'] ?? payload['cost'] ?? payload['usdCost'],
        ),
        'cost_currency': _textValue(payload['costCurrency'], fallback: 'USD'),
        'usd_cost': _doubleValue(payload['usdCost'] ?? payload['cost']),
        'cost_exchange_rate_at_entry':
            _doubleValue(payload['costExchangeRateAtEntry']),
        'original_price': _doubleValue(
          payload['originalPrice'] ?? payload['price'],
        ),
        'original_currency':
            _textValue(payload['originalCurrency'], fallback: 'USD'),
        'usd_price': _doubleValue(payload['usdPrice'] ?? payload['price']),
        'exchange_rate_at_entry':
            _doubleValue(payload['exchangeRateAtEntry']),
        'stock': _doubleValue(payload['stock']),
        'category': _textValue(payload['category'], fallback: 'General'),
        'barcode': _textValue(payload['barcode']),
        'brand': _textValue(payload['brand']),
        'supplier': _textValue(payload['supplier']),
        'description': _textValue(payload['description']),
        'unit': _textValue(payload['unit'], fallback: 'pcs'),
        'quantity_type': _textValue(
          payload['quantityType'],
          fallback: ProductQuantityType.countable.code,
        ),
        'low_stock_threshold': _intValue(payload['lowStockThreshold'],
            fallback: 5),
        'track_stock': _boolValue(payload['trackStock'], fallback: true),
        'is_active': _boolValue(payload['isActive'], fallback: true),
        'image_path': _textValue(payload['imagePath']),
      },
    );

    await db.customStatement(
      'DELETE FROM product_sale_units WHERE product_id = ?;',
      <Object?>[id],
    );
    await db.customStatement(
      'DELETE FROM product_purchase_units WHERE product_id = ?;',
      <Object?>[id],
    );

    await _insertProductUnits(
      db,
      'product_sale_units',
      id,
      payload['saleUnits'],
    );
    await _insertProductUnits(
      db,
      'product_purchase_units',
      id,
      payload['purchaseUnits'],
    );
  }

  static Future<void> _insertProductUnits(
    VentioDriftDatabase db,
    String table,
    String productId,
    Object? unitsValue,
  ) async {
    final units = _payloadMapList(unitsValue);
    for (var index = 0; index < units.length; index += 1) {
      final unit = units[index];
      final unitId = _textValue(unit['id'], fallback: '$table-$index');
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO $table
          (id, product_id, line_no, unit_id, name, conversion_to_base, price,
           original_price, original_currency, barcode, is_default)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('${productId}_${table}_$index'),
          Variable<String>(productId),
          Variable<int>(index),
          Variable<String>(unitId),
          Variable<String>(_textValue(unit['name'])),
          Variable<double>(_doubleValue(unit['conversionToBase'], fallback: 1)),
          Variable<double>(_doubleValue(unit['price'])),
          Variable<double>(
            _doubleValue(unit['originalPrice'], fallback: _doubleValue(unit['price'])),
          ),
          Variable<String>(
            _textValue(unit['originalCurrency'], fallback: 'USD'),
          ),
          Variable<String>(_textValue(unit['barcode'])),
          Variable<int>(_boolValue(unit['isDefault']) ? 1 : 0),
        ],
      );
    }
  }

  static Future<void> _upsertSalePayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'invoice_no': _textValue(payload['invoiceNo']),
        'customer_id': _textValue(payload['customerId']),
        'customer_name': _textValue(payload['customerName']),
        'document_date': _dateString(payload['date']) ?? createdAt,
        'status': _textValue(payload['status'], fallback: 'Paid'),
        'discount': _doubleValue(payload['discount']),
        'original_discount': _doubleValue(
          payload['originalDiscount'],
          fallback: _doubleValue(payload['discount']),
        ),
        'discount_currency':
            _textValue(payload['discountCurrency'], fallback: 'USD'),
        'discount_exchange_rate_at_entry':
            _doubleValue(payload['discountExchangeRateAtEntry']),
        'payment_method':
            _textValue(payload['paymentMethod'], fallback: 'Cash'),
        'payment_status':
            _textValue(payload['paymentStatus'], fallback: 'paid'),
        'invoice_currency':
            _textValue(payload['invoiceCurrency'], fallback: 'USD'),
        'payment_currency':
            _textValue(payload['paymentCurrency'], fallback: 'USD'),
        'exchange_rate_at_payment':
            _doubleValue(payload['exchangeRateAtPayment']),
        'base_currency': _textValue(payload['baseCurrency'], fallback: 'USD'),
        'exchange_rate_at_invoice':
            _doubleValue(payload['exchangeRateAtInvoice'], fallback: 1),
        'transaction_amount': _doubleValue(payload['transactionAmount']),
        'base_amount': _doubleValue(payload['baseAmount']),
        'paid_base_amount': _doubleValue(payload['paidBaseAmount']),
        'exchange_difference_amount':
            _doubleValue(payload['exchangeDifferenceAmount']),
        'paid_amount': _doubleValue(payload['paidAmount']),
        'cash_received_amount': _doubleValue(payload['cashReceivedAmount']),
        'paid_amount_in_payment_currency':
            _doubleValue(payload['paidAmountInPaymentCurrency']),
        'cash_received_amount_in_payment_currency':
            _doubleValue(payload['cashReceivedAmountInPaymentCurrency']),
        'note': _textValue(payload['note']),
      },
    );

    await db.customStatement(
      'DELETE FROM sale_items WHERE sale_id = ?;',
      <Object?>[id],
    );
    await db.customStatement(
      'DELETE FROM sale_item_cost_layer_consumptions '
      'WHERE sale_item_id IN (SELECT id FROM sale_items WHERE sale_id = ?);',
      <Object?>[id],
    );
    await _insertSaleLikeItems(
      db,
      itemTable: 'sale_items',
      parentColumn: 'sale_id',
      parentId: id,
      itemsValue: payload['items'],
      includeConsumptions: true,
      consumptionTable: 'sale_item_cost_layer_consumptions',
      consumptionParentColumn: 'sale_item_id',
    );
  }

  static Future<void> _upsertSaleQuotationPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'quotation_no': _textValue(payload['quotationNo']),
        'customer_id': _textValue(payload['customerId']),
        'customer_name': _textValue(payload['customerName']),
        'document_date': _dateString(payload['date']) ?? createdAt,
        'valid_until': _dateString(payload['validUntil']) ?? '',
        'status': _textValue(payload['status'], fallback: 'Draft'),
        'discount': _doubleValue(payload['discount']),
        'invoice_currency':
            _textValue(payload['invoiceCurrency'], fallback: 'USD'),
        'note': _textValue(payload['note']),
        'converted_sale_id': _textValue(payload['convertedSaleId']),
      },
    );

    await db.customStatement(
      'DELETE FROM sale_quotation_items WHERE sale_quotation_id = ?;',
      <Object?>[id],
    );
    await _insertSaleLikeItems(
      db,
      itemTable: 'sale_quotation_items',
      parentColumn: 'sale_quotation_id',
      parentId: id,
      itemsValue: payload['items'],
    );
  }

  static Future<void> _upsertDeliveryNotePayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'delivery_no': _textValue(payload['deliveryNo']),
        'sale_id': _textValue(payload['saleId']),
        'invoice_no': _textValue(payload['invoiceNo']),
        'customer_id': _textValue(payload['customerId']),
        'customer_name': _textValue(payload['customerName']),
        'document_date': _dateString(payload['date']) ?? createdAt,
        'status': _textValue(payload['status'], fallback: 'Draft'),
        'note': _textValue(payload['note']),
        'delivered_at': _dateString(payload['deliveredAt']) ?? '',
      },
    );

    await db.customStatement(
      'DELETE FROM delivery_note_items WHERE delivery_note_id = ?;',
      <Object?>[id],
    );
    await _insertSaleLikeItems(
      db,
      itemTable: 'delivery_note_items',
      parentColumn: 'delivery_note_id',
      parentId: id,
      itemsValue: payload['items'],
    );
  }

  static Future<void> _upsertPurchasePayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'purchase_no': _textValue(payload['purchaseNo']),
        'supplier_id': _textValue(payload['supplierId']),
        'supplier_name': _textValue(payload['supplierName']),
        'document_date': _dateString(payload['date']) ?? createdAt,
        'status': _textValue(payload['status'], fallback: 'Draft'),
        'note': _textValue(payload['note']),
        'payment_status':
            _textValue(payload['paymentStatus'], fallback: 'paid'),
        'payment_method':
            _textValue(payload['paymentMethod'], fallback: 'Cash'),
        'paid_amount': _doubleValue(payload['paidAmount']),
        'cancel_reason': _textValue(payload['cancelReason']),
        'cancelled_by_device_id':
            _textValue(payload['cancelledByDeviceId']),
        'reversal_applied': _boolValue(payload['reversalApplied']),
        'cancelled_at': _dateString(payload['cancelledAt']) ?? '',
      },
    );

    await db.customStatement(
      'DELETE FROM purchase_items WHERE purchase_id = ?;',
      <Object?>[id],
    );
    await _insertPurchaseItems(
      db,
      purchaseId: id,
      itemsValue: payload['items'],
    );
  }

  static Future<void> _upsertInventoryCountPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'count_no': _textValue(payload['countNo']),
        'created_by': _textValue(payload['createdBy']),
        'warehouse_id': _textValue(payload['warehouseId'], fallback: 'main'),
        'warehouse_name': _textValue(
          payload['warehouseName'],
          fallback: 'Main warehouse',
        ),
        'status': _textValue(payload['status'], fallback: 'open'),
        'notes': _textValue(payload['notes']),
        'approved_at': _dateString(payload['approvedAt']) ?? '',
        'approved_by': _textValue(payload['approvedBy']),
      },
    );

    await db.customStatement(
      'DELETE FROM inventory_count_lines WHERE inventory_count_id = ?;',
      <Object?>[id],
    );
    await _insertInventoryCountLines(
      db,
      inventoryCountId: id,
      linesValue: payload['lines'],
    );
  }

  static Future<void> _upsertBillOfMaterialsPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'name': _textValue(payload['name']),
        'output_product_id': _textValue(payload['outputProductId']),
        'output_product_name': _textValue(payload['outputProductName']),
        'output_quantity': _doubleValue(payload['outputQuantity'], fallback: 1),
        'notes': _textValue(payload['notes']),
        'is_active': _boolValue(payload['isActive'], fallback: true),
      },
    );

    await db.customStatement(
      'DELETE FROM bill_of_materials_lines WHERE bill_of_material_id = ?;',
      <Object?>[id],
    );
    await _insertBillOfMaterialsLines(
      db,
      billOfMaterialId: id,
      linesValue: payload['components'],
    );
  }

  static Future<void> _upsertManufacturingOrderPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'order_no': _textValue(payload['orderNo']),
        'bom_id': _textValue(payload['bomId']),
        'bom_name': _textValue(payload['bomName']),
        'output_product_id': _textValue(payload['outputProductId']),
        'output_product_name': _textValue(payload['outputProductName']),
        'quantity': _doubleValue(payload['quantity']),
        'status': _textValue(payload['status'], fallback: 'completed'),
        'notes': _textValue(payload['notes']),
        'document_date': _dateString(payload['date']) ?? createdAt,
      },
    );
  }

  static Future<void> _upsertRolePayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'name': _textValue(payload['name']),
        'permissions_json': jsonEncode(payload['permissions'] ?? const []),
        'is_system': _boolValue(payload['isSystem']),
      },
    );
  }

  static Future<void> _upsertUserPayload(
    VentioDriftDatabase db,
    String table,
    String entityType,
    Map<String, dynamic> payload, {
    required String id,
    required String payloadJson,
    required String createdAt,
    required String updatedAt,
    required String deletedAt,
    required int sortIndex,
  }) async {
    await _upsertTypedEntityRow(
      db,
      table,
      entityType,
      payload,
      id: id,
      payloadJson: payloadJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      sortIndex: sortIndex,
      typedColumns: <String, Object?>{
        'full_name': _textValue(payload['fullName']),
        'username': _textValue(payload['username']),
        'password_hash': _textValue(payload['passwordHash']),
        'role_id': _textValue(payload['roleId']),
        'extra_permissions_json':
            jsonEncode(payload['extraPermissions'] ?? const []),
        'denied_permissions_json':
            jsonEncode(payload['deniedPermissions'] ?? const []),
        'is_active': _boolValue(payload['isActive'], fallback: true),
        'is_system': _boolValue(payload['isSystem']),
        'last_login_at': _dateString(payload['lastLoginAt']) ?? '',
      },
    );
  }

  static Future<void> _insertSaleLikeItems(
    VentioDriftDatabase db, {
    required String itemTable,
    required String parentColumn,
    required String parentId,
    required Object? itemsValue,
    bool includeConsumptions = false,
    String? consumptionTable,
    String? consumptionParentColumn,
  }) async {
    final items = _payloadMapList(itemsValue);
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      final itemId = '$parentId:$index';
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO $itemTable
          (id, $parentColumn, line_no, product_id, product_name,
           unit_price, quantity, unit_name, base_quantity,
           conversion_to_base, unit_cost, costing_method_at_sale,
           cost_currency, cost_exchange_rate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(itemId),
          Variable<String>(parentId),
          Variable<int>(index),
          Variable<String>(_textValue(item['productId'])),
          Variable<String>(_textValue(item['productName'])),
          Variable<double>(_doubleValue(item['unitPrice'])),
          Variable<double>(_doubleValue(item['quantity'])),
          Variable<String>(_textValue(item['unitName'])),
          Variable<double>(_doubleValue(item['baseQuantity'])),
          Variable<double>(_doubleValue(item['conversionToBase'], fallback: 1)),
          Variable<double>(_doubleValue(item['unitCost'])),
          Variable<String>(
            _textValue(
              item['costingMethodAtSale'],
              fallback: InventoryCostingMethod.weightedAverage.code,
            ),
          ),
          Variable<String>(_textValue(item['costCurrency'], fallback: 'USD')),
          Variable<double>(_doubleValue(item['costExchangeRate'], fallback: 1)),
        ],
      );

      if (!includeConsumptions || consumptionTable == null) continue;
      final consumptions =
          _payloadMapList(item['costLayerConsumptions']);
      final parentColumnName = consumptionParentColumn ?? 'sale_item_id';
      for (var consumptionIndex = 0;
          consumptionIndex < consumptions.length;
          consumptionIndex += 1) {
        final consumption = consumptions[consumptionIndex];
        await db.customInsert(
          '''
          INSERT OR REPLACE INTO $consumptionTable
            (id, $parentColumnName, line_no, layer_id, quantity, unit_cost, currency_code)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>('$itemId:$consumptionIndex'),
            Variable<String>(itemId),
            Variable<int>(consumptionIndex),
            Variable<String>(_textValue(consumption['layerId'])),
            Variable<double>(_doubleValue(consumption['quantity'])),
            Variable<double>(_doubleValue(consumption['unitCost'])),
            Variable<String>(
              _textValue(consumption['currencyCode'], fallback: 'USD'),
            ),
          ],
        );
      }
    }
  }

  static Future<void> _insertPurchaseItems(
    VentioDriftDatabase db, {
    required String purchaseId,
    required Object? itemsValue,
  }) async {
    final items = _payloadMapList(itemsValue);
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO purchase_items
          (id, purchase_id, line_no, product_id, product_name, quantity,
           unit_cost, purchase_unit_id, purchase_unit_name, conversion_to_base,
           original_unit_cost, unit_cost_currency, exchange_rate_at_entry)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('$purchaseId:$index'),
          Variable<String>(purchaseId),
          Variable<int>(index),
          Variable<String>(_textValue(item['productId'])),
          Variable<String>(_textValue(item['productName'])),
          Variable<double>(_doubleValue(item['quantity'])),
          Variable<double>(_doubleValue(item['unitCost'])),
          Variable<String>(_textValue(item['purchaseUnitId'], fallback: 'base')),
          Variable<String>(_textValue(item['purchaseUnitName'])),
          Variable<double>(_doubleValue(item['conversionToBase'], fallback: 1)),
          Variable<double>(_doubleValue(
            item['originalUnitCost'],
            fallback: _doubleValue(item['unitCost']),
          )),
          Variable<String>(
            _textValue(item['unitCostCurrency'], fallback: 'USD'),
          ),
          Variable<double>(_doubleValue(item['exchangeRateAtEntry'])),
        ],
      );
    }
  }

  static Future<void> _insertInventoryCountLines(
    VentioDriftDatabase db, {
    required String inventoryCountId,
    required Object? linesValue,
  }) async {
    final lines = _payloadMapList(linesValue);
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO inventory_count_lines
          (id, inventory_count_id, line_no, product_id, product_name,
           product_code, snapshot_stock, counted_qty, counted_at, counted_by,
           note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('$inventoryCountId:$index'),
          Variable<String>(inventoryCountId),
          Variable<int>(index),
          Variable<String>(_textValue(line['productId'])),
          Variable<String>(_textValue(line['productName'])),
          Variable<String>(_textValue(line['productCode'])),
          Variable<double>(_doubleValue(line['snapshotStock'])),
          Variable<double>(_doubleValue(line['countedQty'])),
          Variable<String>(_dateString(line['countedAt']) ?? ''),
          Variable<String>(_textValue(line['countedBy'])),
          Variable<String>(_textValue(line['note'])),
        ],
      );
    }
  }

  static Future<void> _insertBillOfMaterialsLines(
    VentioDriftDatabase db, {
    required String billOfMaterialId,
    required Object? linesValue,
  }) async {
    final lines = _payloadMapList(linesValue);
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO bill_of_materials_lines
          (id, bill_of_material_id, line_no, product_id, product_name,
           quantity, unit_cost)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('$billOfMaterialId:$index'),
          Variable<String>(billOfMaterialId),
          Variable<int>(index),
          Variable<String>(_textValue(line['productId'])),
          Variable<String>(_textValue(line['productName'])),
          Variable<double>(_doubleValue(line['quantity'])),
          Variable<double>(_doubleValue(line['unitCost'])),
        ],
      );
    }
  }

  static List<Map<String, dynamic>> _payloadMapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Future<void> _migrateComplexTables(VentioDriftDatabase db) async {
    final tables = <String, Future<void> Function(Map<String, dynamic> payload, int sortIndex)>{
      productsKey: (payload, sortIndex) async {
        await _upsertProductPayload(
          db,
          _tableByKey[productsKey]!,
          _entityTypeByKey[productsKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      salesKey: (payload, sortIndex) async {
        await _upsertSalePayload(
          db,
          _tableByKey[salesKey]!,
          _entityTypeByKey[salesKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      saleQuotationsKey: (payload, sortIndex) async {
        await _upsertSaleQuotationPayload(
          db,
          _tableByKey[saleQuotationsKey]!,
          _entityTypeByKey[saleQuotationsKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      deliveryNotesKey: (payload, sortIndex) async {
        await _upsertDeliveryNotePayload(
          db,
          _tableByKey[deliveryNotesKey]!,
          _entityTypeByKey[deliveryNotesKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      purchasesKey: (payload, sortIndex) async {
        await _upsertPurchasePayload(
          db,
          _tableByKey[purchasesKey]!,
          _entityTypeByKey[purchasesKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      inventoryCountsKey: (payload, sortIndex) async {
        await _upsertInventoryCountPayload(
          db,
          _tableByKey[inventoryCountsKey]!,
          _entityTypeByKey[inventoryCountsKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      billsOfMaterialsKey: (payload, sortIndex) async {
        await _upsertBillOfMaterialsPayload(
          db,
          _tableByKey[billsOfMaterialsKey]!,
          _entityTypeByKey[billsOfMaterialsKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['updatedAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
      manufacturingOrdersKey: (payload, sortIndex) async {
        await _upsertManufacturingOrderPayload(
          db,
          _tableByKey[manufacturingOrdersKey]!,
          _entityTypeByKey[manufacturingOrdersKey]!,
          payload,
          id: payload['id']?.toString() ?? '',
          payloadJson: jsonEncode(payload),
          createdAt: _dateString(payload['createdAt']) ??
              _dateString(payload['date']) ??
              DateTime.now().toUtc().toIso8601String(),
          updatedAt: _dateString(payload['updatedAt']) ??
              _dateString(payload['createdAt']) ??
              DateTime.now().toUtc().toIso8601String(),
          deletedAt: _dateString(payload['deletedAt']) ?? '',
          sortIndex: sortIndex,
        );
      },
    };

    for (final entry in tables.entries) {
      final table = _tableByKey[entry.key]!;
      final rows = await db.customSelect('''
        SELECT payload_json, sort_index
        FROM $table
        ORDER BY sort_index ASC, updated_at ASC, id ASC
      ''').get();
      for (final row in rows) {
        final raw = row.read<String>('payload_json');
        if (raw.trim().isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        await entry.value(
          Map<String, dynamic>.from(decoded),
          row.read<int>('sort_index'),
        );
      }
    }
  }

  static Future<void> deleteKey(VentioDriftDatabase db, String key) async {
    final table = _tableByKey[key];
    if (table != null) {
      await db.customStatement('DELETE FROM $table;');
      await db.customStatement(
          'DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
      return;
    }
    await db
        .customStatement('DELETE FROM settings WHERE key = ?;', <Object?>[key]);
    await db.customStatement(
        'DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
  }

  static Future<void> clear(VentioDriftDatabase db) async {
    for (final table in _tableByKey.values) {
      await db.customStatement('DELETE FROM $table;');
    }
    await db.customStatement('DELETE FROM settings;');
    await db.customStatement('DELETE FROM local_key_values;');
  }

  static Future<BusinessSqliteValidationResult> validateAgainstLegacyJson(
    VentioDriftDatabase db, {
    required Map<String, String> legacyEntries,
  }) async {
    final problems = <String>[];
    for (final key in _entityListKeys) {
      final legacyCount = _jsonListLength(legacyEntries[key]);
      final sqliteCount = await _entityCount(db, _tableByKey[key]!);
      if (legacyEntries.containsKey(key) && legacyCount != sqliteCount) {
        problems.add('$key legacy=$legacyCount sqlite=$sqliteCount');
      }
    }

    if (problems.isEmpty) {
      await _setMeta(db, phase3ValidatedMetaKey, 'true');
      return const BusinessSqliteValidationResult(
          ok: true,
          message:
              'Business entity counts match legacy JSON storage source data.');
    }

    await _setMeta(db, phase3ValidatedMetaKey, 'false');
    return BusinessSqliteValidationResult(
        ok: false, message: problems.join('; '));
  }

  static StockMovement _stockMovementFromRow(QueryRow row) {
    final date = _parseDate(_rowText(row, 'movement_date')) ??
        _parseDate(_rowText(row, 'created_at')) ??
        DateTime.now();
    return StockMovement(
      id: _rowText(row, 'id'),
      productId: _rowText(row, 'product_id'),
      productName: _rowText(row, 'product_name'),
      type: _rowText(row, 'movement_type', fallback: 'adjustment'),
      quantity: _rowDouble(row, 'quantity'),
      date: date,
      referenceId: _rowText(row, 'reference_id'),
      referenceNo: _rowText(row, 'reference_no'),
      reason: _rowText(row, 'reason'),
      adjustmentCategory: _rowText(row, 'adjustment_category'),
      notes: _rowText(row, 'notes'),
      evidenceRef: _rowText(row, 'evidence_ref'),
      warehouseId: _rowText(row, 'warehouse_id', fallback: 'main'),
      warehouseName:
          _rowText(row, 'warehouse_name', fallback: 'Main warehouse'),
      unitCost: _rowDouble(row, 'unit_cost'),
      createdAt: _parseDate(_rowText(row, 'created_at')) ?? date,
      updatedAt: _parseDate(_rowText(row, 'updated_at')) ?? date,
      deviceId: _rowText(row, 'device_id'),
      syncStatus: _rowText(row, 'sync_status', fallback: 'synced'),
      storeId: _rowText(row, 'store_id'),
      branchId: _rowText(row, 'branch_id'),
      version: _rowInt(row, 'version', fallback: 1),
      lastModifiedByDeviceId: _rowText(
        row,
        'last_modified_by_device_id',
        fallback: _rowText(row, 'device_id'),
      ),
      reviewedAt: _parseDate(_rowText(row, 'reviewed_at')),
      reviewedBy: _rowText(row, 'reviewed_by'),
      reviewNote: _rowText(row, 'review_note'),
    );
  }

  static AccountTransaction _accountTransactionFromRow(QueryRow row) {
    final date = _parseDate(_rowText(row, 'transaction_date')) ??
        _parseDate(_rowText(row, 'created_at')) ??
        DateTime.now();
    return AccountTransaction(
      id: _rowText(row, 'id'),
      accountType: _rowText(row, 'account_type'),
      accountId: _rowText(row, 'account_id'),
      accountName: _rowText(row, 'account_name'),
      date: date,
      type: _rowText(row, 'transaction_type'),
      referenceId: _rowText(row, 'reference_id'),
      referenceNo: _rowText(row, 'reference_no'),
      debit: _rowDouble(row, 'debit'),
      credit: _rowDouble(row, 'credit'),
      currency: _rowText(row, 'currency', fallback: 'USD'),
      paymentMethod: _rowText(row, 'payment_method'),
      note: _rowText(row, 'note'),
      createdAt: _parseDate(_rowText(row, 'created_at')) ?? date,
      updatedAt: _parseDate(_rowText(row, 'updated_at')) ?? date,
      deletedAt: _parseDate(_rowText(row, 'deleted_at')),
      deviceId: _rowText(row, 'device_id'),
      syncStatus: _rowText(row, 'sync_status', fallback: 'synced'),
      storeId: _rowText(row, 'store_id'),
      branchId: _rowText(row, 'branch_id'),
      version: _rowInt(row, 'version', fallback: 1),
      lastModifiedByDeviceId: _rowText(
        row,
        'last_modified_by_device_id',
        fallback: _rowText(row, 'device_id'),
      ),
    );
  }

  static String _rowText(
    QueryRow row,
    String column, {
    String fallback = '',
  }) {
    final value = row.data[column];
    if (value == null) return fallback;
    final text = value.toString();
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  static double _rowDouble(QueryRow row, String column, {double fallback = 0}) {
    return _doubleValue(row.data[column], fallback: fallback);
  }

  static int _rowInt(QueryRow row, String column, {required int fallback}) {
    return _intValue(row.data[column], fallback: fallback);
  }

  static DateTime? _parseDate(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    return DateTime.tryParse(trimmed);
  }

  static Future<void> _mergeEntityList(
      VentioDriftDatabase db, String key, String jsonText) async {
    final table = _tableByKey[key]!;
    final entityType = _entityTypeByKey[key]!;
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw FormatException('Expected a JSON list for $key');
    }

    final seenIds = <String>{};
    final payloads = <Map<String, dynamic>>[];
    final sortIndices = <int?>[];
    for (var index = 0; index < decoded.length; index += 1) {
      final raw = decoded[index];
      if (raw is! Map) continue;
      final payload = Map<String, dynamic>.from(raw);
      final id = (payload['id']?.toString().isNotEmpty ?? false)
          ? payload['id'].toString()
          : '${entityType}_$index';
      seenIds.add(id);
      payloads.add(payload);
      sortIndices.add(index);
    }

    if (payloads.isNotEmpty) {
      await upsertEntityPayloads(
        db,
        key,
        payloads,
        sortIndices: sortIndices,
      );
    }

    final existingRows = await db.customSelect('SELECT id FROM $table').get();
    for (final row in existingRows) {
      final id = row.read<String>('id');
      if (!seenIds.contains(id)) {
        await db
            .customStatement('DELETE FROM $table WHERE id = ?;', <Object?>[id]);
      }
    }
  }

  static Future<int> _entityCount(VentioDriftDatabase db, String table) async {
    final rows =
        await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
    return rows.first.read<int>('c');
  }

  static Future<bool> _tableHasColumn(
    VentioDriftDatabase db,
    String table,
    String column,
  ) async {
    final rows = await db.customSelect('PRAGMA table_info($table);').get();
    return rows.any((row) => row.data['name']?.toString() == column);
  }

  static int _jsonListLength(String? jsonText) {
    if (jsonText == null || jsonText.isEmpty) return 0;
    try {
      final decoded = jsonDecode(jsonText);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static int _intValue(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _doubleValue(Object? value, {double fallback = 0}) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : fallback;
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : fallback;
    }
    return fallback;
  }

  static bool _boolValue(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return fallback;
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'y';
    }
    if (value == null) return fallback;
    return fallback;
  }

  static String _textValue(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  static Object _sqlValue(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    if (value is bool) return value ? 1 : 0;
    if (value is Iterable && value is! String) return jsonEncode(value);
    if (value is Map) return jsonEncode(value);
    return value;
  }

  static String? _dateString(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static Future<void> _saveLocalMirrorValue(
      VentioDriftDatabase db, String key, String value) async {
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO local_key_values (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  static Future<String?> _metaValue(VentioDriftDatabase db, String key) async {
    final rows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  static Future<void> _setMeta(
      VentioDriftDatabase db, String key, String value) async {
    await db.customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }
}

class BusinessSqliteValidationResult {
  const BusinessSqliteValidationResult(
      {required this.ok, required this.message});
  final bool ok;
  final String message;
}
