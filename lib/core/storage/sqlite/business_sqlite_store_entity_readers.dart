part of 'business_sqlite_store_impl.dart';

Future<List<AccountTransaction>> readAccountTransactions(
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

Future<List<Customer>> readCustomers(VentioDriftDatabase db) async {
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

Future<List<Supplier>> readSuppliers(VentioDriftDatabase db) async {
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

Future<Expense?> readExpenseById(
  VentioDriftDatabase db,
  String id,
) async {
  final normalizedId = id.trim();
  if (normalizedId.isEmpty) return null;
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
      WHERE id = ?
      LIMIT 1
    ''', variables: <Variable<Object>>[Variable<String>(normalizedId)]).get();
  if (rows.isEmpty) return null;
  return Expense.fromJson(Map<String, dynamic>.from(rows.first.data));
}

Future<List<Expense>> readExpenses(VentioDriftDatabase db) async {
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

Future<List<Warehouse>> readWarehouses(VentioDriftDatabase db) async {
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

Future<List<WarehouseTransferOrder>> readWarehouseTransferOrders(
  VentioDriftDatabase db, {
  int? limit,
}) async {
  final safeLimit = limit?.clamp(1, 1000).toInt();
  final rows = await db.customSelect('''
      SELECT id, order_no AS orderNo,
             from_warehouse_id AS fromWarehouseId,
             from_warehouse_name AS fromWarehouseName,
             to_warehouse_id AS toWarehouseId,
             to_warehouse_name AS toWarehouseName,
             document_date AS date, status, notes,
             created_by_user_id AS createdByUserId,
             created_by_user_name AS createdByUserName,
             items_json AS itemsJson,
             created_at AS createdAt, updated_at AS updatedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_transfer_orders
      WHERE deleted_at = ''
      ORDER BY document_date DESC, created_at DESC, id DESC
      ${safeLimit == null ? '' : 'LIMIT ?'}
    ''',
      variables: safeLimit == null
          ? const <Variable<Object>>[]
          : <Variable<Object>>[Variable<int>(safeLimit)]).get();
  return rows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    try {
      data['items'] = jsonDecode(data.remove('itemsJson')?.toString() ?? '[]');
    } catch (_) {
      data['items'] = const <dynamic>[];
    }
    return WarehouseTransferOrder.fromJson(data);
  }).toList(growable: false);
}

Future<List<CatalogItem>> readCatalogItems(
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

Future<List<UserRole>> readRoles(VentioDriftDatabase db) async {
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

Future<List<AppUser>> readUsers(VentioDriftDatabase db) async {
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

Future<List<PriceList>> readPriceLists(VentioDriftDatabase db) async {
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

Future<List<ProductPrice>> readProductPrices(VentioDriftDatabase db) async {
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

Future<List<ProductPriceHistoryEntry>> readProductPriceHistory(
    VentioDriftDatabase db,
    {String productId = '',
    int limit = 200}) async {
  final where = productId.trim().isEmpty ? '' : 'WHERE product_id = ?';
  final rows = await db.customSelect('''
      SELECT id, product_id AS productId, price_list_id AS priceListId,
             unit_id AS unitId, currency_code AS currencyCode,
             old_amount AS oldAmount, new_amount AS newAmount,
             change_percent AS changePercent, change_type AS changeType,
             source, batch_id AS batchId, user_id AS userId,
             user_name AS userName, changed_at AS changedAt,
             created_at AS createdAt, updated_at AS updatedAt
      FROM product_price_history
      $where
      ORDER BY changed_at DESC, id DESC
      LIMIT ?
    ''', variables: <Variable<Object>>[
    if (productId.trim().isNotEmpty) Variable<String>(productId.trim()),
    Variable<int>(limit.clamp(1, 100000).toInt()),
  ]).get();
  return rows
      .map((row) => ProductPriceHistoryEntry.fromJson(
          Map<String, dynamic>.from(row.data)))
      .toList(growable: false);
}

Future<List<ProductPriceOverride>> readProductPriceOverrides(
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

Future<List<ProductCost>> readProductCosts(VentioDriftDatabase db) async {
  // ProductCost is a current snapshot, not an append-only ledger. Older
  // builds could create duplicate rows because the model has no explicit id.
  final rows = await db.customSelect('''
      WITH ranked AS (
        SELECT product_id AS productId, average_cost AS averageCost,
               last_cost AS lastCost, currency_code AS currencyCode,
               created_at AS createdAt, updated_at AS updatedAt,
               ROW_NUMBER() OVER (
                 PARTITION BY product_id
                 ORDER BY updated_at DESC, id DESC
               ) AS rn
        FROM product_costs
        WHERE deleted_at = '' AND trim(product_id) <> ''
      )
      SELECT productId, averageCost, lastCost, currencyCode,
             createdAt, updatedAt
      FROM ranked
      WHERE rn = 1
      ORDER BY productId ASC
    ''').get();
  return rows
      .map((row) => ProductCost.fromJson(Map<String, dynamic>.from(row.data)))
      .toList(growable: false);
}

Future<List<CostingMethodHistory>> readCostingMethodHistory(
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

Future<List<InventoryCostLayer>> readInventoryCostLayers(
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
      WHERE deleted_at = ''
      ORDER BY created_at ASC, id ASC
    ''').get();
  return rows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    // quantity_remaining is authoritative. is_closed is a denormalized cache
    // and must not hide a layer that still has quantity available.
    final remaining = (data['quantityRemaining'] as num? ?? 0).toDouble();
    data['isClosed'] = remaining <= 0.000001;
    return InventoryCostLayer.fromJson(data);
  }).toList(growable: false);
}

Future<List<SupplierProductPrice>> readSupplierProductPrices(
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

Future<List<Product>> readProducts(VentioDriftDatabase db) async {
  final productRows = await db.customSelect('''
      SELECT id, name, code, name_en AS nameEn, name_ar AS nameAr,
             price, cost, original_cost AS originalCost,
             cost_currency AS costCurrency, usd_cost AS usdCost,
             cost_exchange_rate_at_entry AS costExchangeRateAtEntry,
             original_price AS originalPrice,
             original_currency AS originalCurrency,
             usd_price AS usdPrice,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             category, barcode, brand, supplier, description, unit,
             quantity_type AS quantityType,
             low_stock_threshold AS lowStockThreshold,
             CASE WHEN track_stock = 1 THEN 1 ELSE 0 END AS trackStock,
             CASE WHEN expiry_tracking_enabled = 1 THEN 1 ELSE 0 END AS expiryTrackingEnabled,
             CASE WHEN expiry_entry_required = 1 THEN 1 ELSE 0 END AS expiryEntryRequired,
             expiry_alert_days AS expiryAlertDays,
             default_shelf_life_days AS defaultShelfLifeDays,
             minimum_receipt_shelf_life_days AS minimumReceiptShelfLifeDays,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             image_path AS imagePath, tax_profile_id AS taxProfileId, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM products
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final stockByIdentity = await _warehouseInventoryStockByIdentity(db);
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
    saleUnitsByProduct
        .putIfAbsent(
          productId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }

  final purchaseUnitsByProduct = <String, List<Map<String, dynamic>>>{};
  for (final row in purchaseUnitRows) {
    final data = Map<String, dynamic>.from(row.data);
    final productId = data['productId']?.toString() ?? '';
    if (productId.isEmpty) continue;
    data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
    purchaseUnitsByProduct
        .putIfAbsent(
          productId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }

  return productRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['trackStock'] = data['trackStock'] == 1 || data['trackStock'] == true;
    data['expiryTrackingEnabled'] = data['expiryTrackingEnabled'] == 1 ||
        data['expiryTrackingEnabled'] == true;
    data['expiryEntryRequired'] =
        data['expiryEntryRequired'] == 1 || data['expiryEntryRequired'] == true;
    data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
    final storeId = data['storeId']?.toString() ?? '';
    final productId = data['id']?.toString() ?? '';
    final derivedStock = stockByIdentity['$storeId::$productId'];
    data['inventoryStock'] = derivedStock ?? 0;
    data['saleUnits'] = saleUnitsByProduct[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    data['purchaseUnits'] =
        purchaseUnitsByProduct[data['id']?.toString() ?? ''] ??
            const <Map<String, dynamic>>[];
    return Product.fromJson(data);
  }).toList(growable: false);
}

Future<Product?> readProductById(
  VentioDriftDatabase db,
  String productId,
) async {
  final rows = await db.customSelect('''
      SELECT id, name, code, name_en AS nameEn, name_ar AS nameAr,
             price, cost, original_cost AS originalCost,
             cost_currency AS costCurrency, usd_cost AS usdCost,
             cost_exchange_rate_at_entry AS costExchangeRateAtEntry,
             original_price AS originalPrice,
             original_currency AS originalCurrency,
             usd_price AS usdPrice,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             category, barcode, brand, supplier, description, unit,
             quantity_type AS quantityType,
             low_stock_threshold AS lowStockThreshold,
             CASE WHEN track_stock = 1 THEN 1 ELSE 0 END AS trackStock,
             CASE WHEN expiry_tracking_enabled = 1 THEN 1 ELSE 0 END AS expiryTrackingEnabled,
             CASE WHEN expiry_entry_required = 1 THEN 1 ELSE 0 END AS expiryEntryRequired,
             expiry_alert_days AS expiryAlertDays,
             default_shelf_life_days AS defaultShelfLifeDays,
             minimum_receipt_shelf_life_days AS minimumReceiptShelfLifeDays,
             CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             image_path AS imagePath, tax_profile_id AS taxProfileId, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM products
      WHERE id = ?
      LIMIT 1
    ''', variables: <Variable<Object>>[Variable<String>(productId)]).get();
  if (rows.isEmpty) return null;
  final stockByIdentity = await _warehouseInventoryStockByIdentity(db);

  final saleUnitRows = await db.customSelect('''
      SELECT product_id AS productId, line_no AS lineNo, unit_id AS id,
             name, conversion_to_base AS conversionToBase,
             price, original_price AS originalPrice,
             original_currency AS originalCurrency, barcode,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault
      FROM product_sale_units
      WHERE product_id = ?
      ORDER BY line_no ASC
    ''', variables: <Variable<Object>>[Variable<String>(productId)]).get();
  final purchaseUnitRows = await db.customSelect('''
      SELECT product_id AS productId, line_no AS lineNo, unit_id AS id,
             name, conversion_to_base AS conversionToBase,
             price, original_price AS originalPrice,
             original_currency AS originalCurrency, barcode,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault
      FROM product_purchase_units
      WHERE product_id = ?
      ORDER BY line_no ASC
    ''', variables: <Variable<Object>>[Variable<String>(productId)]).get();

  final data = Map<String, dynamic>.from(rows.first.data);
  data['trackStock'] = data['trackStock'] == 1 || data['trackStock'] == true;
  data['expiryTrackingEnabled'] = data['expiryTrackingEnabled'] == 1 ||
      data['expiryTrackingEnabled'] == true;
  data['expiryEntryRequired'] =
      data['expiryEntryRequired'] == 1 || data['expiryEntryRequired'] == true;
  data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
  final storeId = data['storeId']?.toString() ?? '';
  final derivedStock = stockByIdentity['$storeId::$productId'];
  data['inventoryStock'] = derivedStock ?? 0;
  data['saleUnits'] = saleUnitRows.map((row) {
    final item = Map<String, dynamic>.from(row.data);
    item['isDefault'] = item['isDefault'] == 1 || item['isDefault'] == true;
    return item;
  }).toList(growable: false);
  data['purchaseUnits'] = purchaseUnitRows.map((row) {
    final item = Map<String, dynamic>.from(row.data);
    item['isDefault'] = item['isDefault'] == 1 || item['isDefault'] == true;
    return item;
  }).toList(growable: false);
  return Product.fromJson(data);
}

Future<Map<String, Object?>?> findSaleBarcodeProduct(
  VentioDriftDatabase db,
  String code,
) async {
  final normalized = code.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  // A barcode assigned to a sale unit must win over a product-level
  // barcode/code match. Otherwise a derived pack (e.g. 240 g) can be
  // resolved as the base product (e.g. kg) when codes overlap.
  final unitRows = await db.customSelect('''
      SELECT psu.product_id AS productId, psu.unit_id AS unitId
      FROM product_sale_units psu
      INNER JOIN products p ON p.id = psu.product_id
      WHERE p.deleted_at = ''
        AND p.is_active = 1
        AND lower(psu.barcode) = ?
      ORDER BY p.updated_at DESC, psu.line_no ASC, psu.id ASC
      LIMIT 1
    ''', variables: <Variable<Object>>[
    Variable<String>(normalized),
  ]).get();
  if (unitRows.isNotEmpty) {
    final productId = unitRows.first.read<String>('productId');
    final product = await readProductById(db, productId);
    if (product != null) {
      return <String, Object?>{
        'product': product.toJson(),
        'unitId': unitRows.first.read<String>('unitId'),
      };
    }
  }
  final productRows = await db.customSelect('''
      SELECT id, 'base' AS unitId
      FROM products
      WHERE deleted_at = ''
        AND is_active = 1
        AND (lower(code) = ? OR lower(barcode) = ?)
      ORDER BY updated_at DESC, id DESC
      LIMIT 1
    ''', variables: <Variable<Object>>[
    Variable<String>(normalized),
    Variable<String>(normalized),
  ]).get();
  if (productRows.isNotEmpty) {
    final productId = productRows.first.read<String>('id');
    final product = await readProductById(db, productId);
    if (product == null) return null;
    return <String, Object?>{
      'product': product.toJson(),
      'unitId': productRows.first.read<String>('unitId'),
    };
  }
  return null;
}
