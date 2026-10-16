import 'package:drift/drift.dart';

import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/core/contracts/application_session.dart';
import 'assistant_provider.dart';

/// Runs bounded, read-only analyses over an allow-list of business datasets.
///
/// The model selects a dataset and grouping; SQL expressions remain local,
/// fixed in this class, and all user-provided values are bound parameters.
class AssistantBusinessAnalysisService {
  AssistantBusinessAnalysisService._();

  static const int _maximumGroups = 50;
  static const int _maximumFilterCharacters = 120;

  static List<String> datasetsFor(ApplicationSession store) {
    final datasets = <String>[];
    if (store.security.canViewSales) {
      datasets
        ..add('sales')
        ..add('sales_items');
    }
    if (store.security.canViewPurchases) datasets.add('purchases');
    if (store.security.canViewExpenses) datasets.add('expenses');
    if (store.security.canViewInventory || store.security.canViewAccounting) {
      datasets
        ..add('stock_movements')
        ..add('current_stock');
    }
    return List<String>.unmodifiable(datasets);
  }

  static AssistantJsonMap? definitionFor(ApplicationSession store) {
    final datasets = datasetsFor(store);
    if (datasets.isEmpty) return null;
    return <String, Object?>{
      'name': 'business_data_analysis',
      'description':
          'Run a read-only aggregate analysis on available Ventio business data. Use this for trends, rankings, breakdowns, and comparisons that do not fit a single fixed report. Available datasets depend on the signed-in user permissions. Groupings: sales=none/month/day/customer/status/currency/branch; sales_items=none/month/day/customer/product/currency/branch; purchases=none/month/day/supplier/product/document_type/currency/branch; expenses=none/month/day/category/branch; stock_movements=none/month/day/product/warehouse/movement_type/branch; current_stock=none/product/product_warehouse/warehouse/branch. Sales totals use base currency by row. Sales-item amounts use separate invoice and cost currencies; estimated margin is only comparable before invoice discounts and returns. Purchase amounts stay in each line cost currency. Analysis is store-wide unless grouped by branch. For a comparison, call the tool once for each date range and compare matching dimensions and currencies. If no dates are supplied, analyze all available history. Results are aggregated and capped; this tool never returns arbitrary database rows.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'dataset': <String, Object?>{
            'type': 'string',
            'enum': datasets,
            'description': 'The business area to analyze.',
          },
          'group_by': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'none',
              'month',
              'day',
              'customer',
              'supplier',
              'product',
              'product_warehouse',
              'category',
              'warehouse',
              'movement_type',
              'status',
              'document_type',
              'currency',
              'branch',
            ],
            'description':
                'How to group results. Choose a grouping supported by the selected dataset.',
          },
          'from': <String, Object?>{
            'type': 'string',
            'format': 'date',
            'description':
                'Inclusive start date (YYYY-MM-DD). Provide together with to; omit both for all available history.',
          },
          'to': <String, Object?>{
            'type': 'string',
            'format': 'date',
            'description':
                'Inclusive end date (YYYY-MM-DD). Provide together with from; omit both for all available history.',
          },
          'search': <String, Object?>{
            'type': 'string',
            'maxLength': _maximumFilterCharacters,
            'description':
                'Optional partial name or document search, such as a customer, supplier, product, category, warehouse, or invoice number.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'description':
                'Maximum number of groups to return (1 to 50). Defaults to 30.',
          },
        },
        'required': <String>['dataset', 'group_by'],
        'additionalProperties': false,
      },
    };
  }

  static Future<AssistantJsonMap> execute({
    required ApplicationSession store,
    required Map<String, Object?> arguments,
  }) async {
    _requireOnlyArguments(arguments);
    final dataset = _stringArgument(arguments, 'dataset', required: true);
    final groupBy = _stringArgument(arguments, 'group_by', required: true);
    final search = _stringArgument(arguments, 'search',
        maxLength: _maximumFilterCharacters);
    final limit = _integerArgument(arguments, 'limit', fallback: 30);
    if (limit < 1 || limit > _maximumGroups) {
      throw const AssistantBusinessAnalysisException(
        'invalid_arguments',
        'Choose a result limit from 1 to 50.',
      );
    }
    final from = _parseDate(arguments, 'from');
    final to = _parseDate(arguments, 'to');
    if ((from == null) != (to == null)) {
      throw const AssistantBusinessAnalysisException(
        'invalid_date_range',
        'Provide both a start date and an end date, or omit both to use all available history.',
      );
    }
    if (from != null && to != null && from.isAfter(to)) {
      throw const AssistantBusinessAnalysisException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    if (dataset == 'current_stock' && (from != null || to != null)) {
      throw const AssistantBusinessAnalysisException(
        'invalid_date_range',
        'Current stock is a snapshot and does not accept a date range.',
      );
    }

    final allowedDatasets = datasetsFor(store);
    if (!allowedDatasets.contains(dataset)) {
      throw const AssistantBusinessAnalysisException(
        'permission_denied',
        'Your Ventio account does not have permission to analyze this business data.',
      );
    }
    final supportedGroupings = _groupings[dataset];
    if (supportedGroupings == null || !supportedGroupings.contains(groupBy)) {
      throw AssistantBusinessAnalysisException(
        'invalid_arguments',
        'The $groupBy grouping is not supported for the $dataset dataset.',
      );
    }

    final db = SqliteMigrationManager.database;
    if (db == null) {
      throw const AssistantBusinessAnalysisException(
        'business_database_unavailable',
        'Ventio business data is not available for a local read right now.',
      );
    }
    final storeId = store.runtime.identity.storeId.trim();
    if (storeId.isEmpty) {
      throw const AssistantBusinessAnalysisException(
        'active_user_required',
        'Sign in to Ventio and select a store before analyzing business data.',
      );
    }

    final period = from == null
        ? <String, Object?>{'basis': 'all_available_history'}
        : <String, Object?>{
            'from': _dateLabel(from),
            'to': _dateLabel(to!),
            'basis': 'device_local_calendar',
          };
    final result = switch (dataset) {
      'sales' => await _sales(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          from: from,
          to: to,
          limit: limit,
        ),
      'sales_items' => await _salesItems(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          from: from,
          to: to,
          limit: limit,
        ),
      'purchases' => await _purchases(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          from: from,
          to: to,
          limit: limit,
        ),
      'expenses' => await _expenses(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          from: from,
          to: to,
          limit: limit,
        ),
      'stock_movements' => await _stockMovements(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          from: from,
          to: to,
          limit: limit,
        ),
      'current_stock' => await _currentStock(
          db,
          storeId: storeId,
          groupBy: groupBy,
          search: search,
          limit: limit,
        ),
      _ => throw const AssistantBusinessAnalysisException(
          'unknown_dataset', 'This analysis dataset is not available.'),
    };

    return <String, Object?>{
      'dataset': dataset,
      'groupedBy': groupBy,
      'period': period,
      ...result,
    };
  }

  static Future<AssistantJsonMap> _sales(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required DateTime? from,
    required DateTime? to,
    required int limit,
  }) async {
    final groups = <String, String>{
      'none': "'All records'",
      'month': "substr(s.document_date, 1, 7)",
      'day': "substr(s.document_date, 1, 10)",
      'customer':
          "COALESCE(NULLIF(trim(s.customer_name), ''), 'Unknown customer')",
      'status': "lower(trim(s.status))",
      'currency': "COALESCE(NULLIF(upper(trim(s.base_currency)), ''), 'USD')",
      'branch': "COALESCE(NULLIF(trim(s.branch_id), ''), 'Unassigned branch')",
    };
    final where = <String>[
      "s.deleted_at = ''",
      "s.store_id = ?",
      "lower(s.status) NOT IN ('cancelled', 'returned')",
    ];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    _addDateFilter(where, vars, 's.document_date', from, to);
    if (search.isNotEmpty) {
      where.add(
          '(lower(s.customer_name) LIKE ? OR lower(s.invoice_no) LIKE ? OR lower(s.branch_id) LIKE ?)');
      final pattern = _like(search);
      vars
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern));
    }
    final expression = groups[groupBy]!;
    final query = '''
      SELECT $expression AS group_name,
             COALESCE(NULLIF(upper(trim(s.base_currency)), ''), 'USD') AS currency,
             COUNT(*) AS document_count,
             COALESCE(SUM(CASE WHEN s.base_amount > 0 THEN s.base_amount ELSE 0 END), 0) AS gross_amount,
             COALESCE(SUM(CASE WHEN s.paid_base_amount > 0 THEN s.paid_base_amount ELSE 0 END), 0) AS paid_amount,
             COALESCE(SUM(CASE WHEN s.base_amount > s.paid_base_amount THEN s.base_amount - s.paid_base_amount ELSE 0 END), 0) AS outstanding_amount,
             SUM(CASE WHEN s.base_amount <= 0 THEN 1 ELSE 0 END) AS missing_base_amount_count
      FROM sales s
      WHERE ${where.join(' AND ')}
      GROUP BY group_name, currency
      ORDER BY ${_dimensionOrder(groupBy, 'group_name', 'gross_amount')}
      LIMIT ?
    ''';
    final rows = await db.customSelect(query, variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'currencyBasis': 'baseCurrency (reported separately per currency)',
      'excludedStatuses': <String>['cancelled', 'returned'],
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'currency': row['currency'],
                'documentCount': row['document_count'],
                'grossBaseAmount': row['gross_amount'],
                'paidBaseAmount': row['paid_amount'],
                'outstandingBaseAmount': row['outstanding_amount'],
                'missingBaseAmountCount': row['missing_base_amount_count'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static Future<AssistantJsonMap> _purchases(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required DateTime? from,
    required DateTime? to,
    required int limit,
  }) async {
    final groups = <String, String>{
      'none': "'All records'",
      'month': "substr(p.document_date, 1, 7)",
      'day': "substr(p.document_date, 1, 10)",
      'supplier':
          "COALESCE(NULLIF(trim(p.supplier_name), ''), 'Unknown supplier')",
      'product': "COALESCE(NULLIF(trim(pi.product_name), ''), pi.product_id)",
      'document_type': "lower(trim(p.document_type))",
      'currency':
          "COALESCE(NULLIF(upper(trim(pi.unit_cost_currency)), ''), 'USD')",
      'branch': "COALESCE(NULLIF(trim(p.branch_id), ''), 'Unassigned branch')",
    };
    final where = <String>[
      "p.deleted_at = ''",
      'p.store_id = ?',
      "lower(p.status) = 'received'",
    ];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    _addDateFilter(where, vars, 'p.document_date', from, to);
    if (search.isNotEmpty) {
      where.add('''(
        lower(p.supplier_name) LIKE ? OR lower(p.purchase_no) LIKE ? OR lower(p.branch_id) LIKE ? OR
        EXISTS (SELECT 1 FROM purchase_items si
                WHERE si.purchase_id = p.id AND lower(si.product_name) LIKE ?)
      )''');
      final pattern = _like(search);
      vars
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern));
    }
    final expression = groups[groupBy]!;
    final sign =
        "CASE WHEN lower(p.document_type) = 'purchase_return' THEN -1 ELSE 1 END";
    final rows = await db.customSelect('''
      SELECT $expression AS group_name,
             COALESCE(NULLIF(upper(trim(pi.unit_cost_currency)), ''), 'USD') AS currency,
             COUNT(DISTINCT p.id) AS document_count,
             COALESCE(SUM(pi.quantity * pi.unit_cost), 0) AS gross_amount,
             COALESCE(SUM(pi.quantity * pi.unit_cost * $sign), 0) AS signed_amount,
             COALESCE(SUM(pi.quantity * $sign), 0) AS signed_quantity
      FROM purchases p
      LEFT JOIN purchase_items pi ON pi.purchase_id = p.id
      WHERE ${where.join(' AND ')}
      GROUP BY group_name, currency
      ORDER BY ${_dimensionOrder(groupBy, 'group_name', 'signed_amount')}
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'currencyBasis':
          'purchase item unit_cost_currency (reported separately per currency)',
      'includedStatus': 'received',
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'currency': row['currency'],
                'documentCount': row['document_count'],
                'grossLineAmount': row['gross_amount'],
                'signedAmountPurchaseReturnsNegative': row['signed_amount'],
                'signedQuantityPurchaseReturnsNegative': row['signed_quantity'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static Future<AssistantJsonMap> _salesItems(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required DateTime? from,
    required DateTime? to,
    required int limit,
  }) async {
    final groups = <String, String>{
      'none': "'All records'",
      'month': "substr(s.document_date, 1, 7)",
      'day': "substr(s.document_date, 1, 10)",
      'customer':
          "COALESCE(NULLIF(trim(s.customer_name), ''), 'Unknown customer')",
      'product': "COALESCE(NULLIF(trim(si.product_name), ''), si.product_id)",
      'currency':
          "COALESCE(NULLIF(upper(trim(s.invoice_currency)), ''), 'USD')",
      'branch': "COALESCE(NULLIF(trim(s.branch_id), ''), 'Unassigned branch')",
    };
    final where = <String>[
      "s.deleted_at = ''",
      "s.store_id = ?",
      "lower(s.status) NOT IN ('cancelled', 'returned')",
    ];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    _addDateFilter(where, vars, 's.document_date', from, to);
    if (search.isNotEmpty) {
      where.add('''(
        lower(si.product_name) LIKE ? OR lower(s.customer_name) LIKE ? OR
        lower(s.invoice_no) LIKE ? OR lower(s.branch_id) LIKE ?
      )''');
      final pattern = _like(search);
      vars
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern));
    }
    final expression = groups[groupBy]!;
    final rows = await db.customSelect('''
      SELECT $expression AS group_name,
             COALESCE(NULLIF(upper(trim(s.invoice_currency)), ''), 'USD') AS invoice_currency,
             COALESCE(NULLIF(upper(trim(si.cost_currency)), ''), 'USD') AS cost_currency,
             COUNT(DISTINCT s.id) AS invoice_count,
             COALESCE(SUM(si.quantity), 0) AS sold_quantity,
             COALESCE(SUM(si.base_quantity), 0) AS sold_base_quantity,
             COALESCE(SUM(si.quantity * si.unit_price), 0) AS line_sales_amount,
             COALESCE(SUM(si.base_quantity * si.unit_cost), 0) AS recorded_line_cost,
             CASE
               WHEN COALESCE(NULLIF(upper(trim(s.invoice_currency)), ''), 'USD') =
                    COALESCE(NULLIF(upper(trim(si.cost_currency)), ''), 'USD')
               THEN COALESCE(SUM(si.quantity * si.unit_price), 0) -
                    COALESCE(SUM(si.base_quantity * si.unit_cost), 0)
               ELSE NULL
             END AS comparable_margin_estimate
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE ${where.join(' AND ')}
      GROUP BY group_name, invoice_currency, cost_currency
      ORDER BY ${_dimensionOrder(groupBy, 'group_name', 'line_sales_amount')}
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'amountBasis':
          'line sales are quantity × unit price before invoice-level discounts; they use invoiceCurrency. Recorded costs use baseQuantity × unitCost and costCurrency.',
      'excludedStatuses': <String>['cancelled', 'returned'],
      'profitEstimateLimit':
          'Only comparable when invoiceCurrency equals costCurrency. It is before invoice-level discounts and returns, so it is not the accounting gross profit.',
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'invoiceCurrency': row['invoice_currency'],
                'costCurrency': row['cost_currency'],
                'invoiceCount': row['invoice_count'],
                'soldQuantity': row['sold_quantity'],
                'soldBaseQuantity': row['sold_base_quantity'],
                'lineSalesAmountBeforeDocumentDiscount':
                    row['line_sales_amount'],
                'recordedLineCostAmount': row['recorded_line_cost'],
                'comparableGrossMarginEstimateBeforeDiscount':
                    row['comparable_margin_estimate'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static Future<AssistantJsonMap> _expenses(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required DateTime? from,
    required DateTime? to,
    required int limit,
  }) async {
    final groups = <String, String>{
      'none': "'All records'",
      'month': "substr(e.expense_date, 1, 7)",
      'day': "substr(e.expense_date, 1, 10)",
      'category': "COALESCE(NULLIF(trim(e.category), ''), 'Uncategorized')",
      'branch': "COALESCE(NULLIF(trim(e.branch_id), ''), 'Unassigned branch')",
    };
    final where = <String>[
      "e.deleted_at = ''",
      'e.store_id = ?',
      "lower(e.expense_status) = 'posted'",
    ];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    _addDateFilter(where, vars, 'e.expense_date', from, to);
    if (search.isNotEmpty) {
      where.add(
          '(lower(e.title) LIKE ? OR lower(e.category) LIKE ? OR lower(e.branch_id) LIKE ?)');
      final pattern = _like(search);
      vars
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern))
        ..add(Variable<String>(pattern));
    }
    final expression = groups[groupBy]!;
    final rows = await db.customSelect('''
      SELECT $expression AS group_name,
             COUNT(*) AS expense_count,
             COALESCE(SUM(e.amount), 0) AS total_amount
      FROM expenses e
      WHERE ${where.join(' AND ')}
      GROUP BY group_name
      ORDER BY ${_dimensionOrder(groupBy, 'group_name', 'total_amount')}
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'currencyBasis': 'USD reference amount as stored by Ventio',
      'includedStatus': 'posted',
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'expenseCount': row['expense_count'],
                'amountUsdReference': row['total_amount'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static Future<AssistantJsonMap> _stockMovements(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required DateTime? from,
    required DateTime? to,
    required int limit,
  }) async {
    final groups = <String, String>{
      'none': "'All records'",
      'month': "substr(m.movement_date, 1, 7)",
      'day': "substr(m.movement_date, 1, 10)",
      'product': "COALESCE(NULLIF(trim(m.product_name), ''), m.product_id)",
      'warehouse':
          "COALESCE(NULLIF(trim(m.warehouse_name), ''), m.warehouse_id)",
      'movement_type': "lower(trim(m.movement_type))",
      'branch': "COALESCE(NULLIF(trim(m.branch_id), ''), 'Unassigned branch')",
    };
    final where = <String>["m.deleted_at = ''", 'm.store_id = ?'];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    _addDateFilter(where, vars, 'm.movement_date', from, to);
    if (search.isNotEmpty) {
      where.add('''(
        lower(m.product_name) LIKE ? OR lower(m.warehouse_name) LIKE ? OR
        lower(m.movement_type) LIKE ? OR lower(m.reference_no) LIKE ? OR
        lower(m.branch_id) LIKE ?
      )''');
      final pattern = _like(search);
      for (var i = 0; i < 5; i += 1) {
        vars.add(Variable<String>(pattern));
      }
    }
    final expression = groups[groupBy]!;
    final rows = await db.customSelect('''
      SELECT $expression AS group_name,
             COUNT(*) AS movement_count,
             COALESCE(SUM(m.quantity), 0) AS net_quantity,
             COALESCE(SUM(m.quantity * m.unit_cost), 0) AS recorded_value,
             SUM(CASE WHEN m.unit_cost <= 0 THEN 1 ELSE 0 END) AS missing_cost_count
      FROM stock_movements m
      WHERE ${where.join(' AND ')}
      GROUP BY group_name
      ORDER BY ${_dimensionOrder(groupBy, 'group_name', 'recorded_value')}
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'currencyBasis':
          'recorded USD reference unit cost; value is quantity × unit cost',
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'movementCount': row['movement_count'],
                'netQuantity': row['net_quantity'],
                'recordedValueChangeUsdReference': row['recorded_value'],
                'movementsWithoutRecordedCost': row['missing_cost_count'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static Future<AssistantJsonMap> _currentStock(
    VentioDriftDatabase db, {
    required String storeId,
    required String groupBy,
    required String search,
    required int limit,
  }) async {
    final groupByProductWarehouse =
        groupBy == 'product_warehouse' || groupBy == 'none';
    final where = <String>['wi.store_id = ?'];
    final vars = <Variable<Object>>[Variable<String>(storeId)];
    if (search.isNotEmpty) {
      where.add('''(
        lower(COALESCE(p.name, '')) LIKE ? OR lower(wi.product_id) LIKE ? OR
        lower(COALESCE(w.name, '')) LIKE ? OR lower(wi.warehouse_id) LIKE ? OR
        lower(wi.branch_id) LIKE ?
      )''');
      final pattern = _like(search);
      for (var i = 0; i < 5; i += 1) {
        vars.add(Variable<String>(pattern));
      }
    }
    final groupExpression = groupBy == 'product'
        ? "COALESCE(NULLIF(trim(p.name), ''), wi.product_id)"
        : groupBy == 'branch'
            ? "COALESCE(NULLIF(trim(wi.branch_id), ''), 'Unassigned branch')"
            : groupByProductWarehouse
                ? "COALESCE(NULLIF(trim(p.name), ''), wi.product_id) || ' / ' || COALESCE(NULLIF(trim(w.name), ''), wi.warehouse_id) || ' / ' || COALESCE(NULLIF(trim(wi.branch_id), ''), 'Unassigned branch')"
                : "COALESCE(NULLIF(trim(w.name), ''), wi.warehouse_id)";
    final stockOrderBy = groupBy == 'warehouse' || groupBy == 'branch'
        ? 'balance_count DESC, lower(group_name) ASC'
        : 'ABS(COALESCE(SUM(wi.quantity), 0)) DESC, lower(group_name) ASC';
    final rows = await db.customSelect('''
      SELECT $groupExpression AS group_name,
             COUNT(*) AS balance_count,
             COALESCE(SUM(wi.quantity), 0) AS quantity
      FROM warehouse_inventory wi
      LEFT JOIN products p ON p.id = wi.product_id AND p.store_id = wi.store_id
      LEFT JOIN warehouses w ON w.id = wi.warehouse_id AND w.store_id = wi.store_id
      WHERE ${where.join(' AND ')}
      GROUP BY group_name
      ORDER BY $stockOrderBy
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...vars,
      Variable<int>(limit + 1),
    ]).get();
    return <String, Object?>{
      'quantityTotalsCombined': false,
      'note': groupBy == 'warehouse' || groupBy == 'branch'
          ? 'Rows count product balances per warehouse or branch; totals never add quantities across different products.'
          : 'Use the returned rows to compare like products; quantities are not combined across products.',
      'groups': _rows(
          rows,
          limit,
          (row) => <String, Object?>{
                'group': row['group_name'],
                'productWarehouseCount': row['balance_count'],
                if (groupBy != 'warehouse' && groupBy != 'branch')
                  'quantity': row['quantity'],
              }),
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
    };
  }

  static List<AssistantJsonMap> _rows(
    List<QueryRow> rows,
    int limit,
    AssistantJsonMap Function(Map<String, Object?> row) mapRow,
  ) {
    return rows
        .take(limit)
        .map((row) => mapRow(row.data))
        .toList(growable: false);
  }

  static String _dimensionOrder(
          String groupBy, String groupAlias, String metricAlias) =>
      groupBy == 'month' || groupBy == 'day'
          ? '$groupAlias ASC'
          : '$metricAlias DESC, lower($groupAlias) ASC';

  static void _addDateFilter(
    List<String> where,
    List<Variable<Object>> variables,
    String column,
    DateTime? from,
    DateTime? to,
  ) {
    if (from == null || to == null) return;
    final localFrom = DateTime(from.year, from.month, from.day);
    final localToExclusive = DateTime(to.year, to.month, to.day + 1);
    where
      ..add('$column >= ?')
      ..add('$column < ?');
    variables
      ..add(Variable<String>(localFrom.toIso8601String()))
      ..add(Variable<String>(localToExclusive.toIso8601String()));
  }

  static String _stringArgument(
    Map<String, Object?> args,
    String key, {
    bool required = false,
    int maxLength = 160,
  }) {
    final raw = args[key];
    if (raw == null && !required) return '';
    if (raw is! String ||
        raw.trim().isEmpty && required ||
        raw.length > maxLength) {
      throw AssistantBusinessAnalysisException(
        'invalid_arguments',
        'The $key argument must be text of at most $maxLength characters.',
      );
    }
    return raw.trim();
  }

  static int _integerArgument(
    Map<String, Object?> args,
    String key, {
    required int fallback,
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw AssistantBusinessAnalysisException(
      'invalid_arguments',
      'The $key argument must be a whole number.',
    );
  }

  static DateTime? _parseDate(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String) {
      throw AssistantBusinessAnalysisException(
        'invalid_date',
        'The $key value must use YYYY-MM-DD format.',
      );
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      throw AssistantBusinessAnalysisException(
        'invalid_date',
        'The $key value must use YYYY-MM-DD format.',
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final result = DateTime(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      throw AssistantBusinessAnalysisException(
        'invalid_date',
        'The $key value is not a valid calendar date.',
      );
    }
    return result;
  }

  static void _requireOnlyArguments(Map<String, Object?> arguments) {
    const allowed = <String>{
      'dataset',
      'group_by',
      'from',
      'to',
      'search',
      'limit'
    };
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      throw const AssistantBusinessAnalysisException(
        'invalid_arguments',
        'The analysis request contains unsupported arguments.',
      );
    }
  }

  static String _like(String value) => '%${value.trim().toLowerCase()}%';

  static String _dateLabel(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static const Map<String, Set<String>> _groupings = <String, Set<String>>{
    'sales': <String>{
      'none',
      'month',
      'day',
      'customer',
      'status',
      'currency',
      'branch'
    },
    'sales_items': <String>{
      'none',
      'month',
      'day',
      'customer',
      'product',
      'currency',
      'branch',
    },
    'purchases': <String>{
      'none',
      'month',
      'day',
      'supplier',
      'product',
      'document_type',
      'currency',
      'branch',
    },
    'expenses': <String>{'none', 'month', 'day', 'category', 'branch'},
    'stock_movements': <String>{
      'none',
      'month',
      'day',
      'product',
      'warehouse',
      'movement_type',
      'branch',
    },
    'current_stock': <String>{
      'none',
      'product',
      'product_warehouse',
      'warehouse',
      'branch',
    },
  };
}

class AssistantBusinessAnalysisException implements Exception {
  const AssistantBusinessAnalysisException(this.code, this.message);

  final String code;
  final String message;
}
