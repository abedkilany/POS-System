part of 'business_sqlite_store_impl.dart';

Future<void> refreshSummaryTables(
  VentioDriftDatabase db, {
  required DateTime reference,
  bool force = false,
}) async {
  await db.transaction(() async {
    await _rebuildDailyMetrics(db);
    await _rebuildSearchIndex(db);
  });
}

/// Rebuilds the report aggregates without touching the global text-search
/// index. Use this from report reads when an upgrade has not created metrics
/// yet; full rebuilds remain reserved for recovery/sync maintenance.
Future<void> refreshDailyMetrics(VentioDriftDatabase db) async {
  await db.transaction(() async {
    await _rebuildDailyMetrics(db);
  });
}

Future<void> _rebuildDailyMetrics(VentioDriftDatabase db) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.customStatement('DELETE FROM daily_metrics');
  await db.customInsert('''
      INSERT OR REPLACE INTO daily_metrics (
        metric_date, sales_total, sales_profit, sales_count, purchases_total,
        expenses_total, stock_in, stock_out, cash_in, cash_out, updated_at
      )
      SELECT metric_date,
             SUM(sales_total) AS sales_total,
             SUM(sales_profit) AS sales_profit,
             SUM(sales_count) AS sales_count,
             SUM(purchases_total) AS purchases_total,
             SUM(expenses_total) AS expenses_total,
             SUM(stock_in) AS stock_in,
             SUM(stock_out) AS stock_out,
             SUM(cash_in) AS cash_in,
             SUM(cash_out) AS cash_out,
             ? AS updated_at
      FROM (
        SELECT substr(s.document_date, 1, 10) AS metric_date,
               SUM(max(
                 COALESCE(si.unit_price * si.quantity, 0) - s.discount,
                 0
               )) AS sales_total,
               SUM(COALESCE((si.unit_price - si.unit_cost) * si.quantity, 0))
                 - SUM(s.discount) AS sales_profit,
               COUNT(DISTINCT s.id) AS sales_count,
               0 AS purchases_total,
               0 AS expenses_total,
               0 AS stock_in,
               0 AS stock_out,
               0 AS cash_in,
               0 AS cash_out
        FROM sales s
        LEFT JOIN sale_items si ON si.sale_id = s.id
        WHERE s.deleted_at = ''
          AND lower(s.status) NOT IN ('cancelled', 'returned')
          AND trim(s.document_date) <> ''
        GROUP BY substr(s.document_date, 1, 10)
        UNION ALL
        SELECT substr(p.document_date, 1, 10) AS metric_date,
               0, 0, 0,
               SUM(COALESCE(pi.quantity * pi.unit_cost, 0)),
               0, 0, 0, 0, 0
        FROM purchases p
        LEFT JOIN purchase_items pi ON pi.purchase_id = p.id
        WHERE p.deleted_at = ''
          AND lower(p.status) NOT IN ('cancelled', 'returned')
          AND trim(p.document_date) <> ''
        GROUP BY substr(p.document_date, 1, 10)
        UNION ALL
        SELECT substr(expense_date, 1, 10) AS metric_date,
               0, 0, 0, 0, SUM(amount), 0, 0, 0, 0
        FROM expenses
        WHERE deleted_at = ''
          AND lower(expense_status) = 'posted'
          AND trim(expense_date) <> ''
        GROUP BY substr(expense_date, 1, 10)
        UNION ALL
        SELECT substr(movement_date, 1, 10) AS metric_date,
               0, 0, 0, 0, 0,
               SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END),
               SUM(CASE WHEN quantity < 0 THEN abs(quantity) ELSE 0 END),
               0, 0
        FROM stock_movements
        WHERE deleted_at = '' AND trim(movement_date) <> ''
        GROUP BY substr(movement_date, 1, 10)
        UNION ALL
        SELECT substr(occurred_at, 1, 10) AS metric_date,
               0, 0, 0, 0, 0, 0, 0,
               SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END),
               SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END)
        FROM cash_ledger_transactions
        WHERE deleted_at = '' AND trim(occurred_at) <> ''
        GROUP BY substr(occurred_at, 1, 10)
      )
      WHERE trim(metric_date) <> ''
      GROUP BY metric_date
    ''', variables: <Variable<Object>>[Variable<String>(now)]);
}

Future<void> _rebuildSearchIndex(VentioDriftDatabase db) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.customStatement('DELETE FROM search_index');
  await db.customInsert('''
      INSERT OR REPLACE INTO search_index
        (entity_type, entity_id, search_text, updated_at)
      SELECT 'product', id,
             lower(trim(name || ' ' || name_en || ' ' || name_ar || ' ' ||
                        code || ' ' || barcode || ' ' || category || ' ' ||
                        brand || ' ' || supplier || ' ' || unit || ' ' ||
                        description)),
             ?
      FROM products
      WHERE deleted_at = ''
    ''', variables: <Variable<Object>>[Variable<String>(now)]);
  await db.customInsert('''
      INSERT OR REPLACE INTO search_index
        (entity_type, entity_id, search_text, updated_at)
      SELECT 'sale', s.id,
             lower(trim(s.invoice_no || ' ' || s.customer_name || ' ' ||
                        s.payment_method || ' ' || s.payment_status || ' ' ||
                        s.status || ' ' || s.note || ' ' ||
                        COALESCE(group_concat(si.product_name || ' ' ||
                          si.unit_name, ' '), ''))),
             ?
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.deleted_at = ''
      GROUP BY s.id
    ''', variables: <Variable<Object>>[Variable<String>(now)]);
  await db.customInsert('''
      INSERT OR REPLACE INTO search_index
        (entity_type, entity_id, search_text, updated_at)
      SELECT 'stock_movement', id,
             lower(trim(product_name || ' ' || reference_no || ' ' ||
                        movement_type || ' ' || warehouse_name || ' ' ||
                        reason || ' ' || notes)),
             ?
      FROM stock_movements
      WHERE deleted_at = ''
    ''', variables: <Variable<Object>>[Variable<String>(now)]);

  try {
    await db.customStatement('DELETE FROM search_index_fts');
    await db.customInsert('''
        INSERT INTO search_index_fts(entity_type, entity_id, search_text)
        SELECT entity_type, entity_id, search_text FROM search_index
      ''');
  } catch (_) {
    // Fallback search_index table is authoritative when FTS5 is unavailable.
  }
}

Future<void> _upsertSearchIndex(
  VentioDriftDatabase db, {
  required String entityType,
  required String entityId,
  required String searchText,
  required String updatedAt,
  required String deletedAt,
}) async {
  final type = entityType.trim();
  final id = entityId.trim();
  if (type.isEmpty || id.isEmpty) return;
  final normalized = searchText.toLowerCase().trim();
  if (deletedAt.trim().isNotEmpty || normalized.isEmpty) {
    await db.customStatement(
      'DELETE FROM search_index WHERE entity_type = ? AND entity_id = ?',
      <Object?>[type, id],
    );
    return;
  }
  await db.customInsert(
    '''
      INSERT OR REPLACE INTO search_index
        (entity_type, entity_id, search_text, updated_at)
      VALUES (?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(type),
      Variable<String>(id),
      Variable<String>(normalized),
      Variable<String>(updatedAt),
    ],
  );
}

void _upsertSearchIndexIntoBatch(
  Batch batch, {
  required String entityType,
  required String entityId,
  required String searchText,
  required String updatedAt,
  required String deletedAt,
}) {
  final type = entityType.trim();
  final id = entityId.trim();
  if (type.isEmpty || id.isEmpty) return;
  final normalized = searchText.toLowerCase().trim();
  if (deletedAt.trim().isNotEmpty || normalized.isEmpty) {
    batch.customStatement(
      'DELETE FROM search_index WHERE entity_type = ? AND entity_id = ?',
      <Object?>[type, id],
    );
    return;
  }
  batch.customStatement(
    '''
      INSERT OR REPLACE INTO search_index
        (entity_type, entity_id, search_text, updated_at)
      VALUES (?, ?, ?, ?)
      ''',
    <Object?>[type, id, normalized, updatedAt],
  );
}

Future<List<Map<String, Object?>>> _dashboardTopProducts(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      SELECT si.product_name AS label, SUM(si.quantity) AS value
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.deleted_at = ''
        AND lower(s.status) NOT IN ('cancelled', 'returned')
        AND trim(si.product_name) <> ''
      GROUP BY si.product_name
      ORDER BY value DESC
      LIMIT 10
    ''').get();
  return _labelValueRows(rows, labelKey: 'label', valueKey: 'value');
}

Future<List<Map<String, Object?>>> _dashboardTopCustomers(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      $_saleTotalsCte
      SELECT CASE
               WHEN trim(customer_name) = '' THEN 'Walk-in customer'
               ELSE customer_name
             END AS label,
             SUM($_dashboardSaleAmountSql) AS value
      FROM sale_totals
      GROUP BY label
      ORDER BY value DESC
      LIMIT 10
    ''').get();
  return _labelValueRows(rows, labelKey: 'label', valueKey: 'value');
}

Future<List<Map<String, Object?>>> _dashboardRecentOperations(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      WITH
      sale_totals AS (
        SELECT s.id, s.invoice_no, s.customer_name, s.document_date,
               s.discount, s.transaction_amount,
               COALESCE(SUM(si.unit_price * si.quantity), 0) AS line_total
        FROM sales s
        LEFT JOIN sale_items si ON si.sale_id = s.id
        WHERE s.deleted_at = ''
          AND lower(s.status) NOT IN ('cancelled', 'returned')
        GROUP BY s.id
      ),
      purchase_totals AS (
        SELECT p.id, p.purchase_no, p.supplier_name, p.document_date,
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
      SELECT type, title, subtitle, amount, at
      FROM (
        SELECT 'sale' AS type, invoice_no AS title,
               CASE WHEN trim(customer_name) = '' THEN 'Walk-in customer'
                    ELSE customer_name END AS subtitle,
               $_dashboardSaleAmountSql AS amount,
               document_date AS at
        FROM sale_totals
        UNION ALL
        SELECT 'purchase' AS type, purchase_no AS title,
               CASE WHEN trim(supplier_name) = '' THEN 'Purchase'
                    ELSE supplier_name END AS subtitle,
               subtotal AS amount,
               document_date AS at
        FROM purchase_totals
        UNION ALL
        SELECT 'expense' AS type, title,
               CASE WHEN trim(category) = '' THEN 'Unspecified'
                    ELSE category END AS subtitle,
               amount, expense_date AS at
        FROM expenses
        WHERE deleted_at = '' AND lower(expense_status) = 'posted'
        UNION ALL
        SELECT 'stockMovement' AS type,
               CASE WHEN trim(movement_type) = '' THEN 'Movement'
                    ELSE movement_type END AS title,
               product_name AS subtitle,
               abs(quantity) AS amount,
               movement_date AS at
        FROM stock_movements
        WHERE deleted_at = ''
        UNION ALL
        SELECT 'payment' AS type,
               CASE WHEN trim(reference_no) = '' THEN transaction_type
                    ELSE reference_no END AS title,
               account_name AS subtitle,
               abs(debit - credit) AS amount,
               transaction_date AS at
        FROM account_transactions
        WHERE deleted_at = ''
      )
      WHERE trim(at) <> ''
      ORDER BY at DESC
      LIMIT 5
    ''').get();
  return rows
      .map((row) => <String, Object?>{
            'type': _rowText(row, 'type'),
            'title': _rowText(row, 'title'),
            'subtitle': _rowText(row, 'subtitle'),
            'amount': _rowDouble(row, 'amount'),
            'at': _rowText(row, 'at'),
          })
      .toList(growable: false);
}

Future<List<Map<String, Object?>>> _recentStockMovements(
  VentioDriftDatabase db, {
  required int limit,
  String movementType = '',
}) async {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  if (movementType.trim().isNotEmpty) {
    conditions.add('movement_type = ?');
    variables.add(Variable<String>(movementType));
  }
  variables.add(Variable<int>(limit.clamp(1, 500).toInt()));
  final rows = await db.customSelect('''
      SELECT movement_type AS type, product_name AS productName,
             reference_no AS referenceNo, quantity, movement_date AS date
      FROM stock_movements
      WHERE ${conditions.join(' AND ')}
      ORDER BY movement_date DESC, updated_at DESC, id ASC
      LIMIT ?
    ''', variables: variables).get();
  return rows
      .map((row) => <String, Object?>{
            'type': _rowText(row, 'type'),
            'productName': _rowText(row, 'productName'),
            'referenceNo': _rowText(row, 'referenceNo'),
            'quantity': _rowDouble(row, 'quantity'),
            'date': _rowText(row, 'date'),
          })
      .toList(growable: false);
}

Future<List<Map<String, Object?>>> _lowStockRows(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      WITH warehouse_totals AS (
        SELECT store_id, product_id, COALESCE(SUM(quantity), 0) AS quantity
        FROM warehouse_inventory
        GROUP BY store_id, product_id
      )
      SELECT p.name, p.code, COALESCE(wt.quantity, 0) AS stock
      FROM products p
      LEFT JOIN warehouse_totals wt
        ON wt.product_id = p.id AND wt.store_id = p.store_id
      WHERE p.deleted_at = ''
        AND p.track_stock = 1
        AND COALESCE(wt.quantity, 0) <= p.low_stock_threshold
      ORDER BY COALESCE(wt.quantity, 0) ASC, lower(p.name) ASC
      LIMIT 100
    ''').get();
  return rows
      .map((row) => <String, Object?>{
            'name': _rowText(row, 'name'),
            'code': _rowText(row, 'code'),
            'stock': _rowDouble(row, 'stock'),
          })
      .toList(growable: false);
}

Future<List<Map<String, Object?>>> _reportsTopProductLines(
  VentioDriftDatabase db,
) async {
  final rows = await db.customSelect('''
      SELECT si.product_name AS key, SUM(si.quantity) AS value
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.deleted_at = ''
        AND lower(s.status) NOT IN ('cancelled', 'returned')
        AND trim(si.product_name) <> ''
      GROUP BY si.product_name
      ORDER BY value DESC
      LIMIT 20
    ''').get();
  return _keyValueRows(rows);
}

Future<_AccountBalanceSummary> _accountBalanceSummary(
  VentioDriftDatabase db,
  DateTime today,
  DateTime tomorrow,
) async {
  final receivableRows = await db.customSelect('''
      WITH balances AS (
        SELECT lower(account_type) AS accountType, account_id AS accountId,
               SUM(debit - credit) AS balance
        FROM account_transactions
        WHERE deleted_at = ''
          AND lower(account_type) IN ('customer', 'supplier')
          AND trim(account_id) <> ''
        GROUP BY lower(account_type), account_id
      )
      SELECT accountType, accountId, balance
      FROM balances
    ''').get();
  var customerReceivables = 0.0;
  var customerCredits = 0.0;
  var supplierPayables = 0.0;
  var supplierAdvances = 0.0;
  final customerBalances = <String, double>{};
  final supplierBalances = <String, double>{};
  for (final row in receivableRows) {
    final type = _rowText(row, 'accountType');
    final accountId = _rowText(row, 'accountId');
    final balance = _rowDouble(row, 'balance');
    if (type == 'customer' && balance > 0) {
      customerReceivables += balance;
      customerBalances[accountId] = balance;
    } else if (type == 'customer' && balance < 0) {
      customerCredits += balance.abs();
      customerBalances[accountId] = balance;
    }
    if (type == 'supplier' && balance < 0) {
      supplierPayables += balance.abs();
      supplierBalances[accountId] = balance;
    } else if (type == 'supplier' && balance > 0) {
      supplierAdvances += balance;
      supplierBalances[accountId] = balance;
    }
  }

  final topCustomerDebts = await _namedBalanceRows(
    db,
    table: 'customers',
    balances: customerBalances,
    descending: true,
  );
  final topSupplierDebts = await _namedBalanceRows(
    db,
    table: 'suppliers',
    balances: supplierBalances,
    descending: false,
  );
  return _AccountBalanceSummary(
    customerReceivables: customerReceivables,
    customerCredits: customerCredits,
    supplierPayables: supplierPayables,
    supplierAdvances: supplierAdvances,
    topCustomerDebts: topCustomerDebts,
    topSupplierDebts: topSupplierDebts,
  );
}

Future<List<Map<String, Object?>>> _namedBalanceRows(
  VentioDriftDatabase db, {
  required String table,
  required Map<String, double> balances,
  required bool descending,
}) async {
  if (balances.isEmpty) return const <Map<String, Object?>>[];
  final entries = balances.entries.toList()
    ..sort((a, b) =>
        descending ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
  final topEntries = entries.take(20).toList(growable: false);
  final ids = topEntries.map((entry) => entry.key).toList(growable: false);
  final placeholders = List<String>.filled(ids.length, '?').join(', ');
  final rows = await db.customSelect('''
      SELECT id, name
      FROM $table
      WHERE id IN ($placeholders)
    ''',
      variables:
          ids.map((id) => Variable<String>(id)).toList(growable: false)).get();
  final namesById = <String, String>{
    for (final row in rows)
      _rowText(row, 'id'): _rowText(row, 'name', fallback: _rowText(row, 'id')),
  };
  return topEntries
      .map((entry) => <String, Object?>{
            'key': namesById[entry.key] ?? entry.key,
            'value': entry.value,
          })
      .toList(growable: false);
}

Future<int> _pendingSyncCount(
  VentioDriftDatabase db,
  DateTime reference,
) async {
  final staleInProgress =
      reference.subtract(const Duration(seconds: 30)).toIso8601String();
  return _intScalar(db, '''
      SELECT COUNT(*) AS value
      FROM sync_queue
      WHERE status IN ('pending', 'failed')
         OR (status = 'inProgress' AND updated_at < ?)
    ''', variables: <Variable<Object>>[
    Variable<String>(staleInProgress),
  ]);
}

Future<double> _doubleScalar(
  VentioDriftDatabase db,
  String sql, {
  List<Variable<Object>> variables = const <Variable<Object>>[],
}) async {
  final row = await db.customSelect(sql, variables: variables).getSingle();
  return (row.data['value'] as num?)?.toDouble() ?? 0;
}

Future<int> _intScalar(
  VentioDriftDatabase db,
  String sql, {
  List<Variable<Object>> variables = const <Variable<Object>>[],
}) async {
  final row = await db.customSelect(sql, variables: variables).getSingle();
  return (row.data['value'] as num?)?.toInt() ?? 0;
}

Map<String, double> _dateValueMap(DateTime start, int days) {
  return <String, double>{
    for (var i = 0; i < days; i += 1) _dateKey(start.add(Duration(days: i))): 0,
  };
}

List<Map<String, Object?>> _seriesFromDateMap(
  Map<String, double> values,
) {
  return values.entries
      .map((entry) => <String, Object?>{
            'label': _shortDateLabel(entry.key),
            'value': entry.value,
          })
      .toList(growable: false);
}

List<Map<String, Object?>> _sortedSeries(Map<String, double> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries
      .map((entry) => <String, Object?>{
            'label': entry.key,
            'value': entry.value,
          })
      .toList(growable: false);
}

List<Map<String, Object?>> _labelValueRows(
  List<QueryRow> rows, {
  required String labelKey,
  required String valueKey,
}) {
  return rows
      .map((row) => <String, Object?>{
            'label': _rowText(row, labelKey),
            'value': _rowDouble(row, valueKey),
          })
      .where((item) => item['label']?.toString().trim().isNotEmpty ?? false)
      .toList(growable: false);
}

List<Map<String, Object?>> _keyValueRows(List<QueryRow> rows) {
  return rows
      .map((row) => <String, Object?>{
            'key': _rowText(row, 'key'),
            'value': _rowDouble(row, 'value'),
          })
      .where((item) => item['key']?.toString().trim().isNotEmpty ?? false)
      .toList(growable: false);
}

double _averageForWindow(
  Map<String, double> totals,
  DateTime start,
  int days,
) {
  if (days <= 0) return 0;
  var total = 0.0;
  for (var i = 0; i < days; i += 1) {
    total += totals[_dateKey(start.add(Duration(days: i)))] ?? 0;
  }
  return total / days;
}

String _iso(DateTime value) => value.toIso8601String();

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _shortDateLabel(String dateKey) {
  final parts = dateKey.split('-');
  if (parts.length != 3) return dateKey;
  return '${parts[1]}/${parts[2]}';
}

Future<Map<String, List<Map<String, dynamic>>>> _readProductUnitRowsByProduct(
  VentioDriftDatabase db,
  String table,
  List<String> productIds,
) async {
  if (productIds.isEmpty) return const <String, List<Map<String, dynamic>>>{};
  final placeholders = List<String>.filled(productIds.length, '?').join(', ');
  final rows = await db.customSelect('''
      SELECT product_id AS productId, line_no AS lineNo, unit_id AS id,
             name, conversion_to_base AS conversionToBase,
             price, original_price AS originalPrice,
             original_currency AS originalCurrency, barcode,
             CASE WHEN is_default = 1 THEN 1 ELSE 0 END AS isDefault
      FROM $table
      WHERE product_id IN ($placeholders)
      ORDER BY product_id ASC, line_no ASC
    ''',
      variables: productIds
          .map((productId) => Variable<String>(productId))
          .toList(growable: false)).get();
  final unitsByProduct = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final data = Map<String, dynamic>.from(row.data);
    final productId = data['productId']?.toString() ?? '';
    if (productId.isEmpty) continue;
    data['isDefault'] = data['isDefault'] == 1 || data['isDefault'] == true;
    unitsByProduct
        .putIfAbsent(productId, () => <Map<String, dynamic>>[])
        .add(data);
  }
  return unitsByProduct;
}

Future<int> _countWhere(
  VentioDriftDatabase db,
  String table,
  String whereSql,
  List<Variable<Object>> variables,
) async {
  final rows = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM $table WHERE $whereSql',
        variables: variables,
      )
      .get();
  return rows.first.read<int>('c');
}
