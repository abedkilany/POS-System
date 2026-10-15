part of 'business_sqlite_store_impl.dart';

bool isBusinessKey(String key) {
  if (SyncSqliteStore.isSqliteBackedKey(key)) return false;
  if (key.startsWith('sqlite_phase')) return false;
  return true;
}

bool isTypedEntityKey(String key) => _entityListKeys.contains(key);

List<String> get adminEntityKeys => List<String>.unmodifiable(_entityListKeys);

int _safeLimit(int limit) => limit.clamp(1, 500).toInt();

int _safeOffset(int offset) => offset < 0 ? 0 : offset;

String _likePattern(String query) => '%${query.trim().toLowerCase()}%';

String _inPlaceholders(int count) => List<String>.filled(count, '?').join(', ');

Future<BusinessQueryPage<Customer>> queryCustomers(
  VentioDriftDatabase db, {
  String query = '',
  int limit = 50,
  int offset = 0,
  bool includeWalkIn = false,
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  if (!includeWalkIn) {
    conditions.add("id <> 'walk_in'");
    conditions.add("lower(name) <> 'walk-in customer'");
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add('(lower(name) LIKE ? OR lower(phone) LIKE ?)');
    final pattern = _likePattern(normalized);
    variables
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern));
  }
  final whereSql = conditions.join(' AND ');
  final total = await _countWhere(db, 'customers', whereSql, variables);
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final rows = await db.customSelect('''
      SELECT id, name, phone, address, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM customers
      WHERE $whereSql
      ORDER BY lower(name) ASC, updated_at DESC, id ASC
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...variables,
    Variable<int>(safeLimit),
    Variable<int>(safeOffset),
  ]).get();
  return BusinessQueryPage<Customer>(
    items: rows
        .map((row) => Customer.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false),
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<BusinessQueryPage<Supplier>> querySuppliers(
  VentioDriftDatabase db, {
  String query = '',
  int limit = 50,
  int offset = 0,
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add(
      '(lower(name) LIKE ? OR lower(name_en) LIKE ? OR lower(name_ar) LIKE ? OR lower(phone) LIKE ?)',
    );
    final pattern = _likePattern(normalized);
    variables
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern));
  }
  final whereSql = conditions.join(' AND ');
  final total = await _countWhere(db, 'suppliers', whereSql, variables);
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final rows = await db.customSelect('''
      SELECT id, name, name_en AS nameEn, name_ar AS nameAr, phone, address,
             notes, created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM suppliers
      WHERE $whereSql
      ORDER BY lower(name) ASC, updated_at DESC, id ASC
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...variables,
    Variable<int>(safeLimit),
    Variable<int>(safeOffset),
  ]).get();
  return BusinessQueryPage<Supplier>(
    items: rows
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false),
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

_SqlFilter _expenseFilter({
  String query = '',
  String status = 'all',
  bool postedOnly = false,
  DateTime? from,
  DateTime? to,
}) {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  final normalizedStatus = status.trim().toLowerCase();
  if (normalizedStatus.isNotEmpty && normalizedStatus != 'all') {
    conditions.add('lower(expense_status) = ?');
    variables.add(Variable<String>(normalizedStatus));
  }
  if (postedOnly && normalizedStatus != 'posted') {
    conditions.add('lower(expense_status) = ?');
    variables.add(const Variable<String>('posted'));
  }
  if (from != null) {
    conditions.add('expense_date >= ?');
    variables.add(Variable<String>(_iso(from.toLocal())));
  }
  if (to != null) {
    conditions.add('expense_date < ?');
    variables.add(
      Variable<String>(_iso(to.toLocal().add(const Duration(days: 1)))),
    );
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add(
      '(lower(title) LIKE ? OR lower(category) LIKE ? OR lower(notes) LIKE ? OR lower(expense_status) LIKE ? OR lower(cancel_reason) LIKE ?)',
    );
    final pattern = _likePattern(normalized);
    variables
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern))
      ..add(Variable<String>(pattern));
  }
  return _SqlFilter(
    whereSql: conditions.join(' AND '),
    variables: variables,
  );
}

Future<BusinessQueryPage<Expense>> queryExpenses(
  VentioDriftDatabase db, {
  String query = '',
  String status = 'all',
  int limit = 50,
  int offset = 0,
}) async {
  final filter = _expenseFilter(query: query, status: status);
  final whereSql = filter.whereSql;
  final variables = filter.variables;
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final usesTextSearch = query.trim().isNotEmpty;
  final queryLimit = usesTextSearch ? safeLimit + 1 : safeLimit;
  final totalFuture =
      usesTextSearch ? null : _countWhere(db, 'expenses', whereSql, variables);
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
      WHERE $whereSql
      ORDER BY expense_date DESC, updated_at DESC, id ASC
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...variables,
    Variable<int>(queryLimit),
    Variable<int>(safeOffset),
  ]).get();
  final hasMoreSearchRows = usesTextSearch && rows.length > safeLimit;
  final pageRows =
      hasMoreSearchRows ? rows.take(safeLimit).toList(growable: false) : rows;
  return BusinessQueryPage<Expense>(
    items: pageRows
        .map((row) => Expense.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false),
    totalCount: usesTextSearch
        ? safeOffset + pageRows.length + (hasMoreSearchRows ? 1 : 0)
        : await totalFuture!,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<double> sumPostedExpenses(
  VentioDriftDatabase db, {
  String query = '',
  String status = 'all',
}) async {
  final filter = _expenseFilter(
    query: query,
    status: status,
    postedOnly: true,
  );
  final row = await db.customSelect('''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE ${filter.whereSql}
    ''', variables: filter.variables).getSingle();
  return (row.data['total'] as num?)?.toDouble() ?? 0;
}

Future<Map<String, Object?>> assistantExpenseSummary(
  VentioDriftDatabase db, {
  required DateTime from,
  required DateTime to,
}) async {
  final filter = _expenseFilter(
    status: 'posted',
    postedOnly: true,
    from: from,
    to: to,
  );
  final totals = await db.customSelect('''
      SELECT COUNT(*) AS expense_count,
             COALESCE(SUM(amount), 0) AS total_amount
      FROM expenses
      WHERE ${filter.whereSql}
    ''', variables: filter.variables).getSingle();
  final categoryRows = await db.customSelect('''
      SELECT COALESCE(NULLIF(trim(category), ''), 'Uncategorized') AS category,
             COUNT(*) AS expense_count,
             COALESCE(SUM(amount), 0) AS total_amount
      FROM expenses
      WHERE ${filter.whereSql}
      GROUP BY COALESCE(NULLIF(trim(category), ''), 'Uncategorized')
      ORDER BY total_amount DESC, lower(category) ASC
      LIMIT 51
    ''', variables: filter.variables).get();
  final categoryCountRow = await db.customSelect('''
      SELECT COUNT(DISTINCT COALESCE(NULLIF(trim(category), ''), 'Uncategorized'))
        AS category_count
      FROM expenses
      WHERE ${filter.whereSql}
    ''', variables: filter.variables).getSingle();
  final categories = categoryRows.take(50).map((row) {
    return <String, Object?>{
      'category': row.data['category']?.toString() ?? 'Uncategorized',
      'expenseCount': (row.data['expense_count'] as num?)?.toInt() ?? 0,
      'amountUsdReference': (row.data['total_amount'] as num?)?.toDouble() ?? 0,
    };
  }).toList(growable: false);
  final categoryCount =
      (categoryCountRow.data['category_count'] as num?)?.toInt() ?? 0;
  return <String, Object?>{
    'expenseCount': (totals.data['expense_count'] as num?)?.toInt() ?? 0,
    'totalAmountUsdReference':
        (totals.data['total_amount'] as num?)?.toDouble() ?? 0,
    'categoryCount': categoryCount,
    'categories': categories,
    'categoriesTruncated': categoryCount > categories.length,
  };
}

Future<BusinessQueryPage<Product>> queryProducts(
  VentioDriftDatabase db, {
  String query = '',
  String category = '',
  int limit = 50,
  int offset = 0,
  bool activeOnly = false,
  bool stockTrackedOnly = false,
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  if (activeOnly) conditions.add('is_active = 1');
  if (stockTrackedOnly) conditions.add('track_stock = 1');
  final normalizedCategory = category.trim();
  if (normalizedCategory.isNotEmpty && normalizedCategory != 'All') {
    conditions.add('category = ?');
    variables.add(Variable<String>(normalizedCategory));
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add(
      "id IN (SELECT entity_id FROM search_index WHERE entity_type = 'product' AND search_text LIKE ?)",
    );
    variables.add(Variable<String>(_likePattern(normalized)));
  }
  final whereSql = conditions.join(' AND ');
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final usesTextSearch = normalized.isNotEmpty;
  final queryLimit = usesTextSearch ? safeLimit + 1 : safeLimit;
  // Text searches can match many thousands of products. Counting every
  // match before displaying the first page turns a responsive search into a
  // full table scan. Use the extra row fetched below to report whether more
  // results exist; exact totals remain available for non-search views.
  final totalFuture =
      usesTextSearch ? null : _countWhere(db, 'products', whereSql, variables);
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
      WHERE $whereSql
      ORDER BY lower(name) ASC, updated_at DESC, id ASC
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...variables,
    Variable<int>(queryLimit),
    Variable<int>(safeOffset),
  ]).get();
  final hasMoreSearchRows = usesTextSearch && rows.length > safeLimit;
  final pageRows =
      hasMoreSearchRows ? rows.take(safeLimit).toList(growable: false) : rows;
  final productIds =
      pageRows.map((row) => row.read<String>('id')).toList(growable: false);
  final stockByIdentity = await _warehouseInventoryStockByIdentity(
    db,
    productIds: productIds,
  );
  final saleUnitsByProduct = await _readProductUnitRowsByProduct(
    db,
    'product_sale_units',
    productIds,
  );
  final purchaseUnitsByProduct = await _readProductUnitRowsByProduct(
    db,
    'product_purchase_units',
    productIds,
  );
  return BusinessQueryPage<Product>(
    items: pageRows
        .map((row) => _productFromQueryRow(
              row,
              stockByIdentity: stockByIdentity,
              saleUnitsByProduct: saleUnitsByProduct,
              purchaseUnitsByProduct: purchaseUnitsByProduct,
            ))
        .toList(growable: false),
    totalCount: usesTextSearch
        ? safeOffset + pageRows.length + (hasMoreSearchRows ? 1 : 0)
        : await totalFuture!,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<List<String>> queryProductCategories(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      SELECT DISTINCT category
      FROM products
      WHERE deleted_at = '' AND trim(category) <> ''
      ORDER BY category ASC
    ''').get();
  return rows
      .map((row) => row.read<String>('category'))
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
}

Future<Map<String, Object?>> buildDashboardSummary(
  VentioDriftDatabase db, {
  required DateTime reference,
}) async {
  final today = DateTime(reference.year, reference.month, reference.day);
  final tomorrow = today.add(const Duration(days: 1));
  final start7 = today.subtract(const Duration(days: 6));
  final start30 = today.subtract(const Duration(days: 29));
  final sales7 = _dateValueMap(start7, 7);
  final sales30 = _dateValueMap(start30, 30);
  final expenseDailyTotals = <String, double>{};

  var todaySalesTotal = 0.0;
  var todayProfitTotal = 0.0;
  var todayInvoiceCount = 0;
  var salesSince30Days = 0.0;
  var profitSince30Days = 0.0;

  final salesByDay = await db.customSelect('''
      $_saleTotalsCte
      SELECT substr(document_date, 1, 10) AS day,
             SUM($_dashboardSaleAmountSql) AS sales,
             SUM($_saleProfitSql) AS profit,
             COUNT(*) AS invoiceCount
      FROM sale_totals
      WHERE document_date >= ? AND document_date < ?
      GROUP BY substr(document_date, 1, 10)
    ''', variables: <Variable<Object>>[
    Variable<String>(_iso(start30)),
    Variable<String>(_iso(tomorrow)),
  ]).get();
  final todayKey = _dateKey(today);
  for (final row in salesByDay) {
    final day = _rowText(row, 'day');
    final sales = _rowDouble(row, 'sales');
    final profit = _rowDouble(row, 'profit');
    if (sales7.containsKey(day)) sales7[day] = sales;
    if (sales30.containsKey(day)) sales30[day] = sales;
    salesSince30Days += sales;
    profitSince30Days += profit;
    if (day == todayKey) {
      todaySalesTotal = sales;
      todayProfitTotal = profit;
      todayInvoiceCount = _rowInt(row, 'invoiceCount', fallback: 0);
    }
  }

  final totalPurchasesAmount = await _doubleScalar(db, '''
      $_purchaseTotalsCte
      SELECT SUM(subtotal) AS value FROM purchase_totals
    ''');
  const inventoryQuantityExpr = 'COALESCE(wt.quantity, 0)';
  final expenseRows = await db.customSelect('''
      SELECT category, amount, expense_date
      FROM expenses
      WHERE deleted_at = ''
        AND lower(expense_status) = 'posted'
    ''').get();
  final expenseCategories = <String, double>{};
  var totalExpensesAmount = 0.0;
  var todayExpenseTotal = 0.0;
  for (final row in expenseRows) {
    final amount = _rowDouble(row, 'amount');
    final dateText = _rowText(row, 'expense_date');
    final day = dateText.length >= 10 ? dateText.substring(0, 10) : '';
    final categoryText =
        _rowText(row, 'category', fallback: 'Unspecified').trim();
    final category = categoryText.isEmpty ? 'Unspecified' : categoryText;
    totalExpensesAmount += amount;
    expenseCategories[category] = (expenseCategories[category] ?? 0) + amount;
    if (day.isNotEmpty) {
      expenseDailyTotals[day] = (expenseDailyTotals[day] ?? 0) + amount;
    }
    if (day == todayKey) todayExpenseTotal += amount;
  }

  final inventoryRow = await db.customSelect('''
      WITH warehouse_totals AS (
        SELECT store_id, product_id, COALESCE(SUM(quantity), 0) AS quantity
        FROM warehouse_inventory
        GROUP BY store_id, product_id
      ), batch_values AS (
        SELECT bb.store_id, bb.product_id,
               COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carrying_value
        FROM inventory_batch_balances bb
        INNER JOIN inventory_batches b ON b.id = bb.batch_id
          AND b.product_id = bb.product_id AND b.store_id = bb.store_id
        WHERE bb.quantity > 0.000001
          AND b.source_type <> 'inventory_deficit'
          AND b.id NOT LIKE 'deficit:%'
        GROUP BY bb.store_id, bb.product_id
      )
      SELECT COALESCE(SUM(COALESCE(bv.carrying_value, 0)), 0)
               AS inventoryCostValue,
             SUM(CASE WHEN $inventoryQuantityExpr <= p.low_stock_threshold
               THEN 1 ELSE 0 END) AS lowStockCount
      FROM products p
      LEFT JOIN warehouse_totals wt
        ON wt.product_id = p.id AND wt.store_id = p.store_id
      LEFT JOIN batch_values bv
        ON bv.product_id = p.id AND bv.store_id = p.store_id
      WHERE p.deleted_at = '' AND p.track_stock = 1
    ''').getSingle();
  final lowStockRows = await db.customSelect('''
      WITH warehouse_totals AS (
        SELECT store_id, product_id, COALESCE(SUM(quantity), 0) AS quantity
        FROM warehouse_inventory
        GROUP BY store_id, product_id
      )
      SELECT p.name
      FROM products p
      LEFT JOIN warehouse_totals wt
        ON wt.product_id = p.id AND wt.store_id = p.store_id
      WHERE p.deleted_at = ''
        AND p.track_stock = 1
        AND $inventoryQuantityExpr <= p.low_stock_threshold
      ORDER BY lower(p.name) ASC
      LIMIT 20
    ''').get();
  final duplicateCodeCount = await _intScalar(db, '''
      SELECT COUNT(*) AS value
      FROM (
        SELECT lower(code) AS code
        FROM products
        WHERE deleted_at = '' AND trim(code) <> ''
        GROUP BY lower(code)
        HAVING COUNT(*) > 1
      )
    ''');
  final duplicateBarcodeCount = await _intScalar(db, '''
      SELECT COUNT(*) AS value
      FROM (
        SELECT lower(barcode) AS barcode
        FROM products
        WHERE deleted_at = '' AND trim(barcode) <> ''
        GROUP BY lower(barcode)
        HAVING COUNT(*) > 1
      )
    ''');

  return <String, Object?>{
    'todaySalesTotal': todaySalesTotal,
    'todayProfitTotal': todayProfitTotal,
    'todayInvoiceCount': todayInvoiceCount,
    'salesSince30Days': salesSince30Days,
    'profitSince30Days': profitSince30Days,
    'salesLast7Days': _seriesFromDateMap(sales7),
    'salesLast30Days': _seriesFromDateMap(sales30),
    'expenseCategories': _sortedSeries(expenseCategories),
    'topProducts': await _dashboardTopProducts(db),
    'topCustomers': await _dashboardTopCustomers(db),
    'recentOperations': await _dashboardRecentOperations(db),
    'recentStockMovements': await _recentStockMovements(db, limit: 8),
    'totalPurchasesAmount': totalPurchasesAmount,
    'totalExpensesAmount': totalExpensesAmount,
    'inventoryCostValue': _rowDouble(inventoryRow, 'inventoryCostValue'),
    'lowStockCount': _rowInt(inventoryRow, 'lowStockCount', fallback: 0),
    'lowStockNames': lowStockRows
        .map((row) => _rowText(row, 'name', fallback: 'Product'))
        .toList(growable: false),
    'todayExpenseTotal': todayExpenseTotal,
    'last7ExpenseAverage': _averageForWindow(expenseDailyTotals, start7, 7),
    'pendingSyncCount': await _pendingSyncCount(db, reference),
    'blockingConflictCount': duplicateCodeCount + duplicateBarcodeCount,
  };
}

Future<Map<String, Object?>> buildReportsSummary(
  VentioDriftDatabase db, {
  required DateTime reference,
}) async {
  final metricsRows = await _intScalar(
    db,
    'SELECT COUNT(*) AS value FROM daily_metrics',
  );
  if (metricsRows == 0) {
    // Reports only need daily metrics here. Rebuilding the global search
    // index as part of first report open scans every product, sale, and stock
    // movement and was the dominant cost in large databases.
    await refreshDailyMetrics(db);
  }
  final today = DateTime(reference.year, reference.month, reference.day);
  final tomorrow = today.add(const Duration(days: 1));
  final monthStart = DateTime(reference.year, reference.month);
  final nextMonth = DateTime(reference.year, reference.month + 1);
  final accountingNetProfitFuture = db.customSelect(
    '''
      SELECT COALESCE(SUM(
        CASE
          WHEN a.type = 'revenue' THEN jl.credit - jl.debit
          WHEN a.type IN ('cost_of_sales', 'expense') THEN -(jl.debit - jl.credit)
          ELSE 0
        END
      ), 0) AS net_profit
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      INNER JOIN accounts a ON a.id = jl.account_id
      WHERE je.deleted_at = ''
        AND je.status IN ('posted', 'reversed')
        AND datetime(je.entry_date) >= datetime(?)
        AND datetime(je.entry_date) < datetime(?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_iso(monthStart)),
      Variable<String>(_iso(nextMonth)),
    ],
  ).getSingle();
  final cashTotalsFuture = db.customSelect(
    '''
      SELECT
        COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END), 0)
          AS cash_in,
        COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END), 0)
          AS cash_out
      FROM cash_ledger_transactions
      WHERE deleted_at = ''
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_iso(today)),
      Variable<String>(_iso(tomorrow)),
    ],
  ).getSingle();
  final cashByMethodFuture = db.customSelect(
    '''
      SELECT CASE WHEN trim(payment_method) = '' THEN 'not_specified'
                  ELSE payment_method END AS payment_method,
             direction,
             COALESCE(SUM(amount), 0) AS amount
      FROM cash_ledger_transactions
      WHERE deleted_at = ''
        AND occurred_at >= ?
        AND occurred_at < ?
      GROUP BY CASE WHEN trim(payment_method) = '' THEN 'not_specified'
                    ELSE payment_method END,
               direction
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_iso(today)),
      Variable<String>(_iso(tomorrow)),
    ],
  ).get();
  final metricsFuture = db.customSelect('''
      SELECT
        SUM(CASE WHEN metric_date >= ? AND metric_date < ?
          THEN sales_total ELSE 0 END) AS todaySales,
        SUM(CASE WHEN metric_date >= ? AND metric_date < ?
          THEN sales_total ELSE 0 END) AS monthSales,
        SUM(CASE WHEN metric_date >= ? AND metric_date < ?
          THEN purchases_total ELSE 0 END) AS monthPurchases,
        SUM(expenses_total) AS totalExpenses,
        SUM(stock_in) AS movementIn,
        SUM(stock_out) AS movementOut
      FROM daily_metrics
    ''', variables: <Variable<Object>>[
    Variable<String>(_dateKey(today)),
    Variable<String>(_dateKey(tomorrow)),
    Variable<String>(_dateKey(monthStart)),
    Variable<String>(_dateKey(nextMonth)),
    Variable<String>(_dateKey(monthStart)),
    Variable<String>(_dateKey(nextMonth)),
  ]).getSingle();
  final balancesFuture = _accountBalanceSummary(db, today, tomorrow);
  final autoCorrectionsFuture = _recentStockMovements(
    db,
    limit: 100,
    movementType: 'auto_correction',
  );
  final lowStockFuture = _lowStockRows(db);
  final stockMovementsFuture = _recentStockMovements(db, limit: 100);
  final topProductLinesFuture = _reportsTopProductLines(db);
  const inventoryQuantityExpr = 'COALESCE(wt.quantity, 0)';
  final inventoryFuture = db.customSelect('''
      WITH warehouse_totals AS (
        SELECT store_id, product_id, COALESCE(SUM(quantity), 0) AS quantity
        FROM warehouse_inventory
        GROUP BY store_id, product_id
      )
      SELECT COALESCE(SUM(usd_price * $inventoryQuantityExpr), 0)
               AS inventoryRetailValue,
             SUM(CASE WHEN $inventoryQuantityExpr <= p.low_stock_threshold
               THEN 1 ELSE 0 END) AS lowStockCount
      FROM products p
      LEFT JOIN warehouse_totals wt
        ON wt.product_id = p.id AND wt.store_id = p.store_id
      WHERE p.deleted_at = '' AND p.track_stock = 1
    ''').getSingle();
  final metrics = await metricsFuture;
  final accountingNetProfit = await accountingNetProfitFuture;
  final cashTotals = await cashTotalsFuture;
  final cashByMethodRows = await cashByMethodFuture;
  final todayCashInByMethod = <String, double>{};
  final todayCashOutByMethod = <String, double>{};
  for (final row in cashByMethodRows) {
    final method = _rowText(row, 'payment_method', fallback: 'not_specified');
    final amount = _rowDouble(row, 'amount');
    if (_rowText(row, 'direction').toLowerCase() == 'in') {
      todayCashInByMethod[method] = amount;
    } else {
      todayCashOutByMethod[method] = amount;
    }
  }
  final inventory = await inventoryFuture;
  final balances = await balancesFuture;
  final autoCorrections = await autoCorrectionsFuture;
  final lowStock = await lowStockFuture;
  final stockMovements = await stockMovementsFuture;
  final topProductLines = await topProductLinesFuture;

  return <String, Object?>{
    'reference': reference.toIso8601String(),
    'totalExpenses': _rowDouble(metrics, 'totalExpenses'),
    'netProfit': _rowDouble(accountingNetProfit, 'net_profit'),
    'todaySales': _rowDouble(metrics, 'todaySales'),
    'monthSales': _rowDouble(metrics, 'monthSales'),
    'monthPurchases': _rowDouble(metrics, 'monthPurchases'),
    'movementIn': _rowDouble(metrics, 'movementIn'),
    'movementOut': _rowDouble(metrics, 'movementOut'),
    'autoCorrections': autoCorrections,
    'lowStock': lowStock,
    'stockMovements': stockMovements,
    'customerReceivables': balances.customerReceivables,
    'supplierPayables': balances.supplierPayables,
    'inventoryRetailValue': _rowDouble(inventory, 'inventoryRetailValue'),
    'lowStockCount': _rowInt(inventory, 'lowStockCount', fallback: 0),
    'todayCashIn': _rowDouble(cashTotals, 'cash_in'),
    'todayCashOut': _rowDouble(cashTotals, 'cash_out'),
    'todayCashInByMethod': todayCashInByMethod,
    'todayCashOutByMethod': todayCashOutByMethod,
    'topProductLines': topProductLines,
    'topCustomerDebts': balances.topCustomerDebts,
    'topSupplierDebts': balances.topSupplierDebts,
  };
}

Future<Map<String, Object?>> buildAccountingMetrics(
  VentioDriftDatabase db, {
  required DateTime reference,
}) async {
  final today = DateTime(reference.year, reference.month, reference.day);
  final tomorrow = today.add(const Duration(days: 1));
  final balances = await _accountBalanceSummary(db, today, tomorrow);
  final cashRow = await db.customSelect(
    '''
      SELECT
        COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END), 0)
          AS cash_in,
        COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END), 0)
          AS cash_out
      FROM cash_ledger_transactions
      WHERE deleted_at = ''
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
    variables: <Variable<Object>>[
      Variable<String>(today.toUtc().toIso8601String()),
      Variable<String>(tomorrow.toUtc().toIso8601String()),
    ],
  ).getSingle();
  return <String, Object?>{
    'reference': reference.toIso8601String(),
    'customerReceivables': balances.customerReceivables,
    'customerCredits': balances.customerCredits,
    'supplierPayables': balances.supplierPayables,
    'supplierAdvances': balances.supplierAdvances,
    'todayCashIn': _rowDouble(cashRow, 'cash_in'),
    'todayCashOut': _rowDouble(cashRow, 'cash_out'),
  };
}

Future<List<Map<String, Object?>>> queryAccountingAccountRows(
  VentioDriftDatabase db, {
  required String accountType,
  String query = '',
  int limit = 200,
}) async {
  final normalizedType = accountType.trim().toLowerCase();
  final isSupplier = normalizedType == 'supplier';
  final table = isSupplier ? 'suppliers' : 'customers';
  final nameSearch = isSupplier
      ? '''
          lower(a.name) LIKE ? OR lower(a.name_en) LIKE ? OR
          lower(a.name_ar) LIKE ? OR lower(a.phone) LIKE ? OR
          lower(a.address) LIKE ? OR lower(a.id) LIKE ?
        '''
      : '''
          lower(a.name) LIKE ? OR lower(a.phone) LIKE ? OR
          lower(a.address) LIKE ? OR lower(a.id) LIKE ?
        ''';
  final variables = <Variable<Object>>[
    Variable<String>(normalizedType),
  ];
  final normalized = query.trim().toLowerCase();
  final whereParts = <String>["a.deleted_at = ''"];
  if (normalized.isNotEmpty) {
    whereParts.add('($nameSearch)');
    final pattern = _likePattern(normalized);
    final searchCount = isSupplier ? 6 : 4;
    for (var i = 0; i < searchCount; i += 1) {
      variables.add(Variable<String>(pattern));
    }
  }
  variables.add(Variable<int>(_safeLimit(limit)));
  final rows = await db.customSelect('''
      WITH balances AS (
        SELECT account_id AS accountId, SUM(debit - credit) AS balance
        FROM account_transactions
        WHERE deleted_at = ''
          AND lower(account_type) = ?
          AND trim(account_id) <> ''
        GROUP BY account_id
      )
      SELECT a.id, a.name, a.phone, a.address,
             COALESCE(b.balance, 0) AS balance
      FROM $table a
      LEFT JOIN balances b ON b.accountId = a.id
      WHERE ${whereParts.join(' AND ')}
      ORDER BY ABS(COALESCE(b.balance, 0)) DESC, lower(a.name) ASC, a.id ASC
      LIMIT ?
    ''', variables: variables).get();
  return rows.map((row) {
    final phone = _rowText(row, 'phone');
    final address = _rowText(row, 'address');
    return <String, Object?>{
      'id': _rowText(row, 'id'),
      'name': _rowText(row, 'name'),
      'subtitle': <String>[phone, address]
          .where((part) => part.trim().isNotEmpty)
          .join(' - '),
      'balance': _rowDouble(row, 'balance'),
    };
  }).toList(growable: false);
}
