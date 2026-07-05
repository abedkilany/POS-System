import 'dart:convert';

import 'package:drift/drift.dart';

import 'sqlite_database_connection.dart';

/// Drift-backed SQLite foundation for Ventio.
///
/// Phase 3 keeps SQLite as the authoritative local store. legacy JSON storage is retained only
/// as a one-time safety backup source for devices upgrading from older builds.
/// The tables below track migration progress, sync state, and the app key/value
/// data that previously lived in legacy JSON storage.
class VentioDriftDatabase extends GeneratedDatabase {
  VentioDriftDatabase([QueryExecutor? executor])
      : super(executor ?? openVentioSqliteConnection());

  @override
  int get schemaVersion => 15;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => initializeFoundation(),
        onUpgrade: (migrator, from, to) => initializeFoundation(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA synchronous = NORMAL;');
        },
      );

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];

  Future<void> initializeFoundation() async {
    await customStatement('PRAGMA foreign_keys = ON;');
    await customStatement('PRAGMA journal_mode = WAL;');
    await customStatement('PRAGMA synchronous = NORMAL;');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS migration_meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS migration_runs (
        id TEXT PRIMARY KEY NOT NULL,
        phase INTEGER NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        legacy_backup_json TEXT,
        message TEXT NOT NULL DEFAULT ''
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS migration_errors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT,
        phase INTEGER NOT NULL,
        error TEXT NOT NULL,
        stack_trace TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (run_id) REFERENCES migration_runs(id)
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_key_values (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_local_key_values_updated_at ON local_key_values(updated_at);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_settings_updated_at ON settings(updated_at);');

    for (final tableName in <String>[
      'products',
      'customers',
      'suppliers',
      'sales',
      'sale_quotations',
      'delivery_notes',
      'bill_of_materials',
      'manufacturing_orders',
      'inventory_counts',
      'supplier_product_prices',
      'price_lists',
      'product_prices',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'expenses',
      'purchases',
      'warehouses',
      'stock_movements',
      'account_transactions',
      'catalog_categories',
      'catalog_brands',
      'catalog_units',
      'user_roles',
      'app_users',
    ]) {
      await _createBusinessEntityTable(tableName);
    }
    await _ensureOperationalBusinessColumns();
    await _ensureSimpleBusinessColumns();
    await _ensureComplexBusinessColumns();
    await _ensureIdentityBusinessColumns();
    await _ensureLastModifiedByDeviceIdColumns();

    await _createAccountingFoundation();
    await _createSummaryFoundation();

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_events (
        id TEXT PRIMARY KEY NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL DEFAULT '{}',
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        synced_at TEXT NOT NULL DEFAULT '',
        store_epoch INTEGER NOT NULL DEFAULT 1,
        sequence INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_events_sequence ON sync_events(sequence, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_events_entity ON sync_events(entity_type, entity_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_events_synced ON sync_events(is_synced, sequence);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS pending_sync_changes (
        id TEXT PRIMARY KEY NOT NULL,
        event_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        store_epoch INTEGER NOT NULL DEFAULT 1,
        sequence INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (event_id) REFERENCES sync_events(id) ON DELETE CASCADE
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_pending_sync_changes_event ON pending_sync_changes(event_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_pending_sync_changes_sequence ON pending_sync_changes(sequence, created_at);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY NOT NULL,
        change_id TEXT NOT NULL,
        target TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        next_retry_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status, next_retry_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_change ON sync_queue(change_id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id TEXT PRIMARY KEY NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        local_event_id TEXT NOT NULL DEFAULT '',
        remote_event_id TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT '',
        resolution TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        resolved_at TEXT NOT NULL DEFAULT ''
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity ON sync_conflicts(entity_type, entity_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_resolution ON sync_conflicts(resolution, created_at);');

    await customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        const Variable<String>('sqlite_foundation_version'),
        const Variable<String>('7'),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  Future<void> _ensureColumn(
      String tableName, String columnName, String definition) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    final exists =
        rows.any((row) => row.data['name']?.toString() == columnName);
    if (!exists) {
      await customStatement(
          'ALTER TABLE $tableName ADD COLUMN $columnName $definition;');
    }
  }

  Future<bool> _tableHasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    return rows.any((row) => row.data['name']?.toString() == columnName);
  }

  Future<List<String>> _tableColumns(String tableName) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    return rows
        .map((row) => row.data['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic>? _decodePayloadJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> _migratePayloadJsonRows(
    String tableName,
    Map<String, Object?> Function(
      Map<String, dynamic> payload,
      Map<String, Object?> row,
    ) buildUpdates,
  ) async {
    if (!await _tableHasColumn(tableName, 'payload_json')) return;
    final rows = await customSelect('''
      SELECT *
      FROM $tableName
      WHERE payload_json <> ''
    ''').get();
    if (rows.isEmpty) return;

    await transaction(() async {
      for (final row in rows) {
        final payload = _decodePayloadJson(row.read<String>('payload_json'));
        if (payload == null) continue;
        final updates =
            buildUpdates(payload, Map<String, Object?>.from(row.data));
        if (updates.isEmpty) continue;
        await _updateRowColumns(tableName, row.read<String>('id'), updates);
      }
    });
  }

  Future<void> _updateRowColumns(
    String tableName,
    String id,
    Map<String, Object?> updates,
  ) async {
    final entries = updates.entries.toList(growable: false);
    if (entries.isEmpty) return;
    final assignments = entries.map((entry) => '${entry.key} = ?').join(', ');
    await customUpdate(
      'UPDATE $tableName SET $assignments WHERE id = ?;',
      variables: <Variable<Object>>[
        for (final entry in entries) Variable<Object>(_sqlValue(entry.value)),
        Variable<String>(id),
      ],
    );
  }

  Object? _sqlValue(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map || value is List) return jsonEncode(value);
    return value;
  }

  String? _stringOrNull(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  String _stringValue(Object? value, {String fallback = ''}) {
    return _stringOrNull(value) ?? fallback;
  }

  double? _doubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return double.tryParse(text);
  }

  double _doubleValue(Object? value, {double fallback = 0}) {
    return _doubleOrNull(value) ?? fallback;
  }

  int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return int.tryParse(text);
  }

  int _intValue(Object? value, {int fallback = 0}) {
    return _intOrNull(value) ?? fallback;
  }

  bool? _boolTrueOrNull(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? true : null;
    if (value is num) return value != 0 ? true : null;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null') return null;
    if (text == 'true' || text == '1') return true;
    return null;
  }

  String _jsonStringValue(Object? value, {String fallback = '[]'}) {
    if (value == null) return fallback;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == 'null') return fallback;
      return text;
    }
    return jsonEncode(value);
  }

  Future<void> rebuildBusinessTablesWithoutPayloadJson() async {
    final tablesToRebuild = <String>[
      'products',
      'customers',
      'suppliers',
      'sales',
      'sale_quotations',
      'delivery_notes',
      'bill_of_materials',
      'manufacturing_orders',
      'inventory_counts',
      'supplier_product_prices',
      'price_lists',
      'product_prices',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'expenses',
      'purchases',
      'warehouses',
      'stock_movements',
      'account_transactions',
      'catalog_categories',
      'catalog_brands',
      'catalog_units',
      'user_roles',
      'app_users',
    ];

    final pending = <String>[];
    for (final table in tablesToRebuild) {
      if (await _tableHasColumn(table, 'payload_json')) {
        pending.add(table);
      }
    }
    if (pending.isEmpty) return;

    await customStatement('PRAGMA foreign_keys = OFF;');
    try {
      final legacyTables = <String, String>{};
      for (final table in pending) {
        final legacyTable = '${table}__legacy_payload_json';
        await customStatement('ALTER TABLE $table RENAME TO $legacyTable;');
        legacyTables[table] = legacyTable;
      }

      for (final table in pending) {
        await _createBusinessEntityTable(table);
      }
      await _ensureOperationalBusinessColumns();
      await _ensureSimpleBusinessColumns();
      await _ensureComplexBusinessColumns();
      await _ensureIdentityBusinessColumns();
      await _ensureLastModifiedByDeviceIdColumns();

      for (final table in pending) {
        final legacyTable = legacyTables[table]!;
        final sourceColumns = await _tableColumns(legacyTable);
        final targetColumns = await _tableColumns(table);
        final copyColumns = sourceColumns
            .where((column) =>
                column.isNotEmpty &&
                column != 'payload_json' &&
                targetColumns.contains(column))
            .toList(growable: false);
        if (copyColumns.isNotEmpty) {
          final joinedColumns = copyColumns.join(', ');
          await customStatement('''
            INSERT INTO $table ($joinedColumns)
            SELECT $joinedColumns
            FROM $legacyTable;
          ''');
        }
        await customStatement('DROP TABLE $legacyTable;');
      }
    } finally {
      await customStatement('PRAGMA foreign_keys = ON;');
    }
  }

  Future<void> _ensureOperationalBusinessColumns() async {
    await _ensureStockMovementColumns();
    await _ensureAccountTransactionColumns();
    await _backfillOperationalBusinessColumnsIfNeeded();
  }

  Future<void> _ensureSimpleBusinessColumns() async {
    await _ensureCustomerColumns();
    await _ensureSupplierColumns();
    await _ensureExpenseColumns();
    await _ensureWarehouseColumns();
    await _ensureCatalogColumns('catalog_categories');
    await _ensureCatalogColumns('catalog_brands');
    await _ensureCatalogColumns('catalog_units');
    await _ensurePriceListColumns();
    await _ensureProductPriceColumns();
    await _ensureProductPriceOverrideColumns();
    await _ensureProductCostColumns();
    await _ensureCostingMethodHistoryColumns();
    await _ensureInventoryCostLayerColumns();
    await _ensureSupplierProductPriceColumns();
    await _backfillSimpleBusinessColumnsIfNeeded();
  }

  Future<void> _ensureComplexBusinessColumns() async {
    await _ensureProductColumns();
    await _ensureProductUnitTables();
    await _ensureSaleColumns();
    await _ensureSaleItemTables();
    await _ensureSaleQuotationColumns();
    await _ensureSaleQuotationItemTables();
    await _ensureDeliveryNoteColumns();
    await _ensureDeliveryNoteItemTables();
    await _ensurePurchaseColumns();
    await _ensurePurchaseItemTable();
    await _ensureInventoryCountColumns();
    await _ensureInventoryCountLineTable();
    await _ensureBillOfMaterialsColumns();
    await _ensureBillOfMaterialsLineTable();
    await _ensureManufacturingOrderColumns();
  }

  Future<void> _ensureIdentityBusinessColumns() async {
    await _ensureRoleColumns();
    await _ensureUserColumns();
  }

  Future<void> _ensureLastModifiedByDeviceIdColumns() async {
    for (final table in <String>{
      'products',
      'customers',
      'suppliers',
      'sales',
      'sale_quotations',
      'delivery_notes',
      'bill_of_materials',
      'manufacturing_orders',
      'expenses',
      'purchases',
      'warehouses',
      'inventory_counts',
      'supplier_product_prices',
      'price_lists',
      'product_prices',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'catalog_categories',
      'catalog_brands',
      'catalog_units',
    }) {
      await _ensureColumn(
        table,
        'last_modified_by_device_id',
        "TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _ensureProductColumns() async {
    await _ensureColumn('products', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'name_en', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'name_ar', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'original_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'cost_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('products', 'usd_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'cost_exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'original_price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'original_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('products', 'usd_price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'stock', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'category', "TEXT NOT NULL DEFAULT 'General'");
    await _ensureColumn('products', 'barcode', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'brand', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'supplier', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'description', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'unit', "TEXT NOT NULL DEFAULT 'pcs'");
    await _ensureColumn(
        'products', 'quantity_type', "TEXT NOT NULL DEFAULT 'countable'");
    await _ensureColumn(
        'products', 'low_stock_threshold', 'INTEGER NOT NULL DEFAULT 5');
    await _ensureColumn(
        'products', 'track_stock', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn('products', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn('products', 'image_path', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);');
  }

  Future<void> _ensureProductUnitTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS product_sale_units (
        id TEXT PRIMARY KEY NOT NULL,
        product_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        unit_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL DEFAULT 0,
        original_price REAL NOT NULL DEFAULT 0,
        original_currency TEXT NOT NULL DEFAULT 'USD',
        barcode TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        CHECK (is_default IN (0, 1))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_sale_units_product_line ON product_sale_units(product_id, line_no);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS product_purchase_units (
        id TEXT PRIMARY KEY NOT NULL,
        product_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        unit_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL DEFAULT 0,
        original_price REAL NOT NULL DEFAULT 0,
        original_currency TEXT NOT NULL DEFAULT 'USD',
        barcode TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        CHECK (is_default IN (0, 1))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_purchase_units_product_line ON product_purchase_units(product_id, line_no);');
  }

  Future<void> _ensureSaleColumns() async {
    await _ensureColumn('sales', 'invoice_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'status', "TEXT NOT NULL DEFAULT 'Paid'");
    await _ensureColumn('sales', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'original_discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'discount_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'discount_exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'payment_method', "TEXT NOT NULL DEFAULT 'Cash'");
    await _ensureColumn(
        'sales', 'payment_status', "TEXT NOT NULL DEFAULT 'paid'");
    await _ensureColumn(
        'sales', 'invoice_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'payment_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'exchange_rate_at_payment', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'base_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'exchange_rate_at_invoice', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'sales', 'transaction_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'base_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'paid_base_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'exchange_difference_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'paid_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'cash_received_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'paid_amount_in_payment_currency', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'cash_received_amount_in_payment_currency',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'note', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id, document_date);');
  }

  Future<void> _ensureSaleItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY NOT NULL,
        sale_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_line ON sale_items(sale_id, line_no);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_item_cost_layer_consumptions (
        id TEXT PRIMARY KEY NOT NULL,
        sale_item_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        layer_id TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_item_consumptions_item_line ON sale_item_cost_layer_consumptions(sale_item_id, line_no);');
  }

  Future<void> _ensureSaleQuotationColumns() async {
    await _ensureColumn(
        'sale_quotations', 'quotation_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'valid_until', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn(
        'sale_quotations', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sale_quotations', 'invoice_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('sale_quotations', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'converted_sale_id', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureSaleQuotationItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_quotation_items (
        id TEXT PRIMARY KEY NOT NULL,
        sale_quotation_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (sale_quotation_id) REFERENCES sale_quotations(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_quotation_items_quote_line ON sale_quotation_items(sale_quotation_id, line_no);');
  }

  Future<void> _ensureDeliveryNoteColumns() async {
    await _ensureColumn(
        'delivery_notes', 'delivery_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'sale_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'invoice_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn('delivery_notes', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'delivered_at', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureDeliveryNoteItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS delivery_note_items (
        id TEXT PRIMARY KEY NOT NULL,
        delivery_note_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (delivery_note_id) REFERENCES delivery_notes(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_delivery_note_items_note_line ON delivery_note_items(delivery_note_id, line_no);');
  }

  Future<void> _ensurePurchaseColumns() async {
    await _ensureColumn('purchases', 'purchase_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchases', 'supplier_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'supplier_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchases', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn('purchases', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'payment_status', "TEXT NOT NULL DEFAULT 'paid'");
    await _ensureColumn(
        'purchases', 'payment_method', "TEXT NOT NULL DEFAULT 'Cash'");
    await _ensureColumn('purchases', 'paid_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'purchases', 'cancel_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'cancelled_by_device_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'reversal_applied', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'purchases', 'cancelled_at', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(document_date);');
  }

  Future<void> _ensurePurchaseItemTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id TEXT PRIMARY KEY NOT NULL,
        purchase_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        purchase_unit_id TEXT NOT NULL DEFAULT 'base',
        purchase_unit_name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        original_unit_cost REAL NOT NULL DEFAULT 0,
        unit_cost_currency TEXT NOT NULL DEFAULT 'USD',
        exchange_rate_at_entry REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase_line ON purchase_items(purchase_id, line_no);');
  }

  Future<void> _ensureInventoryCountColumns() async {
    await _ensureColumn(
        'inventory_counts', 'count_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'created_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('inventory_counts', 'warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'inventory_counts', 'status', "TEXT NOT NULL DEFAULT 'open'");
    await _ensureColumn(
        'inventory_counts', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'approved_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'approved_by', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureInventoryCountLineTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS inventory_count_lines (
        id TEXT PRIMARY KEY NOT NULL,
        inventory_count_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        product_code TEXT NOT NULL DEFAULT '',
        snapshot_stock REAL NOT NULL DEFAULT 0,
        counted_qty REAL,
        counted_at TEXT NOT NULL DEFAULT '',
        counted_by TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (inventory_count_id) REFERENCES inventory_counts(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_count_lines_count_line ON inventory_count_lines(inventory_count_id, line_no);');
  }

  Future<void> _ensureBillOfMaterialsColumns() async {
    await _ensureColumn(
        'bill_of_materials', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_product_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_quantity', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'bill_of_materials', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureBillOfMaterialsLineTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS bill_of_materials_lines (
        id TEXT PRIMARY KEY NOT NULL,
        bill_of_material_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (bill_of_material_id) REFERENCES bill_of_materials(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_bom_lines_bom_line ON bill_of_materials_lines(bill_of_material_id, line_no);');
  }

  Future<void> _ensureManufacturingOrderColumns() async {
    await _ensureColumn(
        'manufacturing_orders', 'order_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'bom_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'bom_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('manufacturing_orders', 'output_product_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('manufacturing_orders', 'output_product_name',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'quantity', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'manufacturing_orders', 'status', "TEXT NOT NULL DEFAULT 'completed'");
    await _ensureColumn(
        'manufacturing_orders', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'document_date', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureStockMovementColumns() async {
    await _ensureColumn(
        'stock_movements', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'product_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'movement_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'quantity', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'stock_movements', 'movement_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reference_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reference_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'adjustment_category', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('stock_movements', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'evidence_ref', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('stock_movements', 'warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'stock_movements', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('stock_movements', 'last_modified_by_device_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reviewed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reviewed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'review_note', "TEXT NOT NULL DEFAULT ''");

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date ON stock_movements(product_id, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_product ON stock_movements(product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_type_date ON stock_movements(movement_type, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse_date ON stock_movements(warehouse_id, movement_date);');
  }

  Future<void> _ensureAccountTransactionColumns() async {
    await _ensureColumn(
        'account_transactions', 'account_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'account_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'account_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'transaction_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'transaction_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'reference_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'reference_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'debit', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'account_transactions', 'credit', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'account_transactions', 'currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'account_transactions', 'payment_method', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('account_transactions', 'last_modified_by_device_id',
        "TEXT NOT NULL DEFAULT ''");

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_account_date ON account_transactions(account_type, account_id, transaction_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_reference ON account_transactions(reference_id, reference_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_type_date ON account_transactions(transaction_type, transaction_date);');
  }

  Future<void> _ensureCustomerColumns() async {
    await _ensureColumn('customers', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('customers', 'phone', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('customers', 'address', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureSupplierColumns() async {
    await _ensureColumn('suppliers', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'name_en', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'name_ar', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'phone', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'address', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'notes', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureExpenseColumns() async {
    await _ensureColumn('expenses', 'title', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'category', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('expenses', 'original_amount', 'REAL');
    await _ensureColumn(
        'expenses', 'original_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'expenses', 'exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('expenses', 'expense_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'expenses', 'expense_status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn(
        'expenses', 'cancel_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'expenses', 'cancelled_by_device_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'cancelled_at', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);');
  }

  Future<void> _ensureWarehouseColumns() async {
    await _ensureColumn('warehouses', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouses', 'code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouses', 'location', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'warehouses', 'is_default', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'warehouses', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureCatalogColumns(String tableName) async {
    await _ensureColumn(tableName, 'name_en', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(tableName, 'name_ar', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(tableName, 'code', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensurePriceListColumns() async {
    await _ensureColumn('price_lists', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('price_lists', 'code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'price_lists', 'is_default', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'price_lists', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureProductPriceColumns() async {
    await _ensureColumn(
        'product_prices', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_prices', 'price_list_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_prices', 'unit_id', "TEXT NOT NULL DEFAULT 'base'");
    await _ensureColumn(
        'product_prices', 'base_currency_code', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'product_prices', 'base_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_prices', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureProductPriceOverrideColumns() async {
    await _ensureColumn('product_price_overrides', 'product_price_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('product_price_overrides', 'currency_code',
        "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'product_price_overrides', 'amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_price_overrides', 'mode', "TEXT NOT NULL DEFAULT 'fixed'");
    await _ensureColumn(
        'product_price_overrides', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureProductCostColumns() async {
    await _ensureColumn(
        'product_costs', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_costs', 'average_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_costs', 'last_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_costs', 'currency_code', "TEXT NOT NULL DEFAULT 'USD'");
  }

  Future<void> _ensureCostingMethodHistoryColumns() async {
    await _ensureColumn('costing_method_history', 'method',
        "TEXT NOT NULL DEFAULT 'weighted_average'");
    await _ensureColumn(
        'costing_method_history', 'effective_from', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'costing_method_history', 'effective_to', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'costing_method_history', 'reason', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureInventoryCostLayerColumns() async {
    await _ensureColumn(
        'inventory_cost_layers', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_cost_layers', 'product_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('inventory_cost_layers', 'quantity_received',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('inventory_cost_layers', 'quantity_remaining',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'inventory_cost_layers', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('inventory_cost_layers', 'currency_code',
        "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'inventory_cost_layers', 'exchange_rate', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'inventory_cost_layers', 'purchase_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('inventory_cost_layers', 'purchase_item_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('inventory_cost_layers', 'source_type',
        "TEXT NOT NULL DEFAULT 'purchase'");
    await _ensureColumn(
        'inventory_cost_layers', 'source_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_cost_layers', 'is_closed', 'INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _ensureSupplierProductPriceColumns() async {
    await _ensureColumn(
        'supplier_product_prices', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'supplier_product_prices', 'supplier_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'supplier_product_prices', 'cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'supplier_product_prices', 'currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('supplier_product_prices', 'is_preferred',
        'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'supplier_product_prices', 'supplier_sku', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('supplier_product_prices', 'min_order_qty', 'REAL');
    await _ensureColumn('supplier_product_prices', 'lead_time_days', 'INTEGER');
    await _ensureColumn(
        'supplier_product_prices', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('supplier_product_prices', 'price_history_json',
        "TEXT NOT NULL DEFAULT '[]'");
  }

  Future<void> _ensureRoleColumns() async {
    await _ensureColumn('user_roles', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'user_roles', 'permissions_json', "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn(
        'user_roles', 'is_system', 'INTEGER NOT NULL DEFAULT 0');
    await _migratePayloadJsonRows('user_roles', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'permissions_json': _jsonStringValue(
          payload['permissions'],
          fallback: _stringValue(row['permissions_json'], fallback: '[]'),
        ),
        'is_system': _boolTrueOrNull(payload['isSystem']) == true
            ? 1
            : _intValue(row['is_system'], fallback: 0),
      };
    });
  }

  Future<void> _ensureUserColumns() async {
    await _ensureColumn('app_users', 'full_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('app_users', 'username', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'app_users', 'password_hash', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('app_users', 'role_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'app_users', 'extra_permissions_json', "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn(
        'app_users', 'denied_permissions_json', "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn('app_users', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn('app_users', 'is_system', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'app_users', 'last_login_at', "TEXT NOT NULL DEFAULT ''");
    await _migratePayloadJsonRows('app_users', (payload, row) {
      return <String, Object?>{
        'full_name': _stringOrNull(payload['fullName']) ??
            _stringValue(row['full_name']),
        'username':
            _stringOrNull(payload['username']) ?? _stringValue(row['username']),
        'password_hash': _stringOrNull(payload['passwordHash']) ??
            _stringValue(row['password_hash']),
        'role_id':
            _stringOrNull(payload['roleId']) ?? _stringValue(row['role_id']),
        'extra_permissions_json': _jsonStringValue(
          payload['extraPermissions'],
          fallback: _stringValue(row['extra_permissions_json'], fallback: '[]'),
        ),
        'denied_permissions_json': _jsonStringValue(
          payload['deniedPermissions'],
          fallback:
              _stringValue(row['denied_permissions_json'], fallback: '[]'),
        ),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
        'is_system': _boolTrueOrNull(payload['isSystem']) == true
            ? 1
            : _intValue(row['is_system'], fallback: 0),
        'last_login_at': _stringOrNull(payload['lastLoginAt']) ??
            _stringValue(row['last_login_at']),
      };
    });
  }

  Future<void> _backfillOperationalBusinessColumnsIfNeeded() async {
    final done =
        await _metaValue('sqlite_operational_columns_v1_backfilled') == 'true';
    if (done) return;
    await _migratePayloadJsonRows('stock_movements', (payload, row) {
      if (_stringValue(row['product_id']).isNotEmpty &&
          _stringValue(row['movement_date']).isNotEmpty &&
          _stringValue(row['movement_type']).isNotEmpty) {
        return const <String, Object?>{};
      }
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'product_name': _stringOrNull(payload['productName']) ??
            _stringValue(row['product_name']),
        'movement_type': _stringOrNull(payload['type']) ??
            _stringValue(row['movement_type']),
        'quantity':
            _doubleOrNull(payload['quantity']) ?? _doubleValue(row['quantity']),
        'movement_date': _stringOrNull(payload['date']) ??
            _stringOrNull(payload['createdAt']) ??
            _stringValue(row['movement_date'],
                fallback: _stringValue(row['created_at'])),
        'reference_id': _stringOrNull(payload['referenceId']) ??
            _stringOrNull(payload['saleId']) ??
            _stringOrNull(payload['purchaseId']) ??
            _stringValue(row['reference_id']),
        'reference_no': _stringOrNull(payload['referenceNo']) ??
            _stringValue(row['reference_no']),
        'reason':
            _stringOrNull(payload['reason']) ?? _stringValue(row['reason']),
        'adjustment_category': _stringOrNull(payload['adjustmentCategory']) ??
            _stringOrNull(payload['category']) ??
            _stringValue(row['adjustment_category']),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
        'evidence_ref': _stringOrNull(payload['evidenceRef']) ??
            _stringValue(row['evidence_ref']),
        'warehouse_id': _stringOrNull(payload['warehouseId']) ??
            _stringValue(row['warehouse_id'], fallback: 'main'),
        'warehouse_name': _stringOrNull(payload['warehouseName']) ??
            _stringValue(row['warehouse_name'], fallback: 'Main warehouse'),
        'unit_cost': _doubleOrNull(payload['unitCost']) ??
            _doubleValue(row['unit_cost']),
        'last_modified_by_device_id': _stringOrNull(
              payload['lastModifiedByDeviceId'],
            ) ??
            _stringOrNull(payload['deviceId']) ??
            _stringValue(row['last_modified_by_device_id']),
        'reviewed_at': _stringOrNull(payload['reviewedAt']) ??
            _stringValue(row['reviewed_at']),
        'reviewed_by': _stringOrNull(payload['reviewedBy']) ??
            _stringValue(row['reviewed_by']),
        'review_note': _stringOrNull(payload['reviewNote']) ??
            _stringValue(row['review_note']),
      };
    });

    await _migratePayloadJsonRows('account_transactions', (payload, row) {
      if (_stringValue(row['account_id']).isNotEmpty &&
          _stringValue(row['transaction_date']).isNotEmpty &&
          _stringValue(row['transaction_type']).isNotEmpty) {
        return const <String, Object?>{};
      }
      return <String, Object?>{
        'account_type': _stringOrNull(payload['accountType']) ??
            _stringValue(row['account_type']),
        'account_id': _stringOrNull(payload['accountId']) ??
            _stringValue(row['account_id']),
        'account_name': _stringOrNull(payload['accountName']) ??
            _stringValue(row['account_name']),
        'transaction_date': _stringOrNull(payload['date']) ??
            _stringOrNull(payload['createdAt']) ??
            _stringValue(row['transaction_date'],
                fallback: _stringValue(row['created_at'])),
        'transaction_type': _stringOrNull(payload['type']) ??
            _stringValue(row['transaction_type']),
        'reference_id': _stringOrNull(payload['referenceId']) ??
            _stringValue(row['reference_id']),
        'reference_no': _stringOrNull(payload['referenceNo']) ??
            _stringValue(row['reference_no']),
        'debit': _doubleOrNull(payload['debit']) ?? _doubleValue(row['debit']),
        'credit':
            _doubleOrNull(payload['credit']) ?? _doubleValue(row['credit']),
        'currency': _stringOrNull(payload['currency']) ??
            _stringValue(row['currency'], fallback: 'USD'),
        'payment_method': _stringOrNull(payload['paymentMethod']) ??
            _stringValue(row['payment_method']),
        'note': _stringOrNull(payload['note']) ?? _stringValue(row['note']),
        'deleted_at': _stringOrNull(payload['deletedAt']) ??
            _stringValue(row['deleted_at']),
        'last_modified_by_device_id': _stringOrNull(
              payload['lastModifiedByDeviceId'],
            ) ??
            _stringOrNull(payload['deviceId']) ??
            _stringValue(row['last_modified_by_device_id']),
      };
    });

    await _setMeta('sqlite_operational_columns_v1_backfilled', 'true');
  }

  Future<void> _backfillSimpleBusinessColumnsIfNeeded() async {
    final done =
        await _metaValue('sqlite_operational_columns_v2_backfilled') == 'true';
    if (done) return;
    await _migratePayloadJsonRows('customers', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'phone': _stringOrNull(payload['phone']) ?? _stringValue(row['phone']),
        'address':
            _stringOrNull(payload['address']) ?? _stringValue(row['address']),
      };
    });

    await _migratePayloadJsonRows('suppliers', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'name_en':
            _stringOrNull(payload['nameEn']) ?? _stringValue(row['name_en']),
        'name_ar':
            _stringOrNull(payload['nameAr']) ?? _stringValue(row['name_ar']),
        'phone': _stringOrNull(payload['phone']) ?? _stringValue(row['phone']),
        'address':
            _stringOrNull(payload['address']) ?? _stringValue(row['address']),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
      };
    });

    await _migratePayloadJsonRows('expenses', (payload, row) {
      return <String, Object?>{
        'title': _stringOrNull(payload['title']) ?? _stringValue(row['title']),
        'category':
            _stringOrNull(payload['category']) ?? _stringValue(row['category']),
        'amount':
            _doubleOrNull(payload['amount']) ?? _doubleValue(row['amount']),
        'original_amount': _doubleOrNull(payload['originalAmount']) ??
            _doubleOrNull(payload['amount']) ??
            _doubleValue(row['original_amount']),
        'original_currency': _stringOrNull(payload['originalCurrency']) ??
            _stringValue(row['original_currency'], fallback: 'USD'),
        'exchange_rate_at_entry':
            _doubleOrNull(payload['exchangeRateAtEntry']) ??
                _doubleValue(row['exchange_rate_at_entry']),
        'expense_date': _stringOrNull(payload['date']) ??
            _stringValue(row['expense_date'],
                fallback: _stringValue(row['created_at'])),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
        'expense_status': _stringOrNull(payload['status']) ??
            _stringValue(row['expense_status']),
        'cancel_reason': _stringOrNull(payload['cancelReason']) ??
            _stringValue(row['cancel_reason']),
        'cancelled_by_device_id':
            _stringOrNull(payload['cancelledByDeviceId']) ??
                _stringValue(row['cancelled_by_device_id']),
        'cancelled_at': _stringOrNull(payload['cancelledAt']) ??
            _stringValue(row['cancelled_at']),
      };
    });

    await _migratePayloadJsonRows('warehouses', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        'location':
            _stringOrNull(payload['location']) ?? _stringValue(row['location']),
        'is_default': _boolTrueOrNull(payload['isDefault']) == true
            ? 1
            : _intValue(row['is_default'], fallback: 0),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    for (final table in <String>{
      'catalog_categories',
      'catalog_brands',
      'catalog_units'
    }) {
      await _migratePayloadJsonRows(table, (payload, row) {
        return <String, Object?>{
          'name_en':
              _stringOrNull(payload['nameEn']) ?? _stringValue(row['name_en']),
          'name_ar':
              _stringOrNull(payload['nameAr']) ?? _stringValue(row['name_ar']),
          'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        };
      });
    }

    await _migratePayloadJsonRows('price_lists', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        'is_default': _boolTrueOrNull(payload['isDefault']) == true
            ? 1
            : _intValue(row['is_default'], fallback: 0),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_prices', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'price_list_id': _stringOrNull(payload['priceListId']) ??
            _stringValue(row['price_list_id']),
        'unit_id': _stringOrNull(payload['unitId']) ??
            _stringValue(row['unit_id'], fallback: 'base'),
        'base_currency_code': _stringOrNull(payload['baseCurrencyCode']) ??
            _stringValue(row['base_currency_code'], fallback: 'USD'),
        'base_amount': _doubleOrNull(payload['baseAmount']) ??
            _doubleValue(row['base_amount']),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_price_overrides', (payload, row) {
      return <String, Object?>{
        'product_price_id': _stringOrNull(payload['productPriceId']) ??
            _stringValue(row['product_price_id']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
        'amount':
            _doubleOrNull(payload['amount']) ?? _doubleValue(row['amount']),
        'mode': _stringOrNull(payload['mode']) ??
            _stringValue(row['mode'], fallback: 'fixed'),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_costs', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'average_cost': _doubleOrNull(payload['averageCost']) ??
            _doubleValue(row['average_cost']),
        'last_cost': _doubleOrNull(payload['lastCost']) ??
            _doubleValue(row['last_cost']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
      };
    });

    await _migratePayloadJsonRows('costing_method_history', (payload, row) {
      return <String, Object?>{
        'method': _stringOrNull(payload['method']) ??
            _stringValue(row['method'], fallback: 'weighted_average'),
        'effective_from': _stringOrNull(payload['effectiveFrom']) ??
            _stringValue(row['effective_from']),
        'effective_to': _stringOrNull(payload['effectiveTo']) ??
            _stringValue(row['effective_to']),
        'reason':
            _stringOrNull(payload['reason']) ?? _stringValue(row['reason']),
      };
    });

    await _migratePayloadJsonRows('inventory_cost_layers', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'product_name': _stringOrNull(payload['productName']) ??
            _stringValue(row['product_name']),
        'quantity_received': _doubleOrNull(payload['quantityReceived']) ??
            _doubleValue(row['quantity_received']),
        'quantity_remaining': _doubleOrNull(payload['quantityRemaining']) ??
            _doubleValue(row['quantity_remaining']),
        'unit_cost': _doubleOrNull(payload['unitCost']) ??
            _doubleValue(row['unit_cost']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
        'exchange_rate': _doubleOrNull(payload['exchangeRate']) ??
            _doubleValue(row['exchange_rate'], fallback: 1),
        'purchase_id': _stringOrNull(payload['purchaseId']) ??
            _stringValue(row['purchase_id']),
        'purchase_item_id': _stringOrNull(payload['purchaseItemId']) ??
            _stringValue(row['purchase_item_id']),
        'source_type': _stringOrNull(payload['sourceType']) ??
            _stringValue(row['source_type'], fallback: 'purchase'),
        'source_id': _stringOrNull(payload['sourceId']) ??
            _stringValue(row['source_id']),
        'is_closed': _boolTrueOrNull(payload['isClosed']) == true
            ? 1
            : _intValue(row['is_closed'], fallback: 0),
      };
    });

    await _migratePayloadJsonRows('supplier_product_prices', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'supplier_id': _stringOrNull(payload['supplierId']) ??
            _stringValue(row['supplier_id']),
        'cost': _doubleOrNull(payload['cost']) ??
            _doubleOrNull(payload['unitCost']) ??
            _doubleValue(row['cost']),
        'currency': _stringOrNull(payload['currency']) ??
            _stringValue(row['currency'], fallback: 'USD'),
        'is_preferred': _boolTrueOrNull(payload['isPreferred']) == true
            ? 1
            : _intValue(row['is_preferred'], fallback: 0),
        'supplier_sku': _stringOrNull(payload['supplierSku']) ??
            _stringOrNull(payload['supplierSKU']) ??
            _stringOrNull(payload['supplierCode']) ??
            _stringValue(row['supplier_sku']),
        'min_order_qty': _doubleOrNull(payload['minOrderQty']) ??
            _doubleOrNull(payload['minimumOrderQty']) ??
            _doubleValue(row['min_order_qty']),
        'lead_time_days': _intOrNull(payload['leadTimeDays']) ??
            _intOrNull(payload['lead_time_days']) ??
            _intValue(row['lead_time_days']),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
        'price_history_json': _jsonStringValue(
          payload['priceHistory'],
          fallback: _stringValue(row['price_history_json'], fallback: '[]'),
        ),
      };
    });

    await _setMeta('sqlite_operational_columns_v2_backfilled', 'true');
  }

  Future<String?> _metaValue(String key) async {
    final rows = await customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<void> _setMeta(String key, String value) async {
    await customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }


  Future<void> _createSummaryFoundation() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS dashboard_daily_summary (
        day TEXT PRIMARY KEY NOT NULL,
        sales_total REAL NOT NULL DEFAULT 0,
        profit_total REAL NOT NULL DEFAULT 0,
        invoice_count INTEGER NOT NULL DEFAULT 0,
        expenses_total REAL NOT NULL DEFAULT 0,
        purchases_total REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_dashboard_daily_summary_updated ON dashboard_daily_summary(updated_at);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS dashboard_expense_category_summary (
        category TEXT PRIMARY KEY NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_dashboard_expense_category_amount ON dashboard_expense_category_summary(amount);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS stock_summary (
        product_id TEXT PRIMARY KEY NOT NULL,
        product_name TEXT NOT NULL DEFAULT '',
        stock REAL NOT NULL DEFAULT 0,
        low_stock_threshold REAL NOT NULL DEFAULT 0,
        cost_value REAL NOT NULL DEFAULT 0,
        retail_value REAL NOT NULL DEFAULT 0,
        is_low_stock INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_summary_low ON stock_summary(is_low_stock, product_name);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS customer_balance_summary (
        customer_id TEXT PRIMARY KEY NOT NULL,
        customer_name TEXT NOT NULL DEFAULT '',
        balance REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customer_balance_summary_balance ON customer_balance_summary(balance);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_balance_summary (
        supplier_id TEXT PRIMARY KEY NOT NULL,
        supplier_name TEXT NOT NULL DEFAULT '',
        balance REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_supplier_balance_summary_balance ON supplier_balance_summary(balance);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS dashboard_kv_summary (
        key TEXT PRIMARY KEY NOT NULL,
        value_json TEXT NOT NULL DEFAULT '{}',
        updated_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createAccountingFoundation() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        subtype TEXT NOT NULL DEFAULT '',
        parent_id TEXT NOT NULL DEFAULT '',
        normal_balance TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'USD',
        is_system INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL DEFAULT 1,
        CHECK (type IN ('asset', 'liability', 'equity', 'revenue', 'cost_of_sales', 'expense')),
        CHECK (normal_balance IN ('debit', 'credit')),
        CHECK (is_system IN (0, 1)),
        CHECK (is_active IN (0, 1))
      );
    ''');

    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_active ON accounts(code) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts(type, subtype);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounts_parent ON accounts(parent_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounts_store_branch ON accounts(store_id, branch_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id TEXT PRIMARY KEY NOT NULL,
        entry_no TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT NOT NULL DEFAULT '',
        reference_no TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'posted',
        source TEXT NOT NULL DEFAULT 'system',
        created_by TEXT NOT NULL DEFAULT '',
        posted_at TEXT NOT NULL DEFAULT '',
        reversed_entry_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL DEFAULT 1,
        CHECK (status IN ('draft', 'posted', 'void', 'reversed')),
        CHECK (source IN ('system', 'manual', 'import', 'reversal'))
      );
    ''');

    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_entry_no_active ON journal_entries(entry_no) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_entries_date ON journal_entries(entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON journal_entries(reference_type, reference_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON journal_entries(status, entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_store_branch ON journal_entries(store_id, branch_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id TEXT PRIMARY KEY NOT NULL,
        entry_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        account_id TEXT NOT NULL,
        account_code TEXT NOT NULL DEFAULT '',
        account_name TEXT NOT NULL DEFAULT '',
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'USD',
        memo TEXT NOT NULL DEFAULT '',
        party_type TEXT NOT NULL DEFAULT '',
        party_id TEXT NOT NULL DEFAULT '',
        party_name TEXT NOT NULL DEFAULT '',
        cost_center_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE,
        FOREIGN KEY (account_id) REFERENCES accounts(id),
        CHECK (debit >= 0),
        CHECK (credit >= 0),
        CHECK (NOT (debit > 0 AND credit > 0)),
        CHECK (debit > 0 OR credit > 0)
      );
    ''');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(entry_id, line_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);');
    await _addColumnIfMissing(
        'journal_lines', 'cost_center_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_party ON journal_lines(party_type, party_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_cost_center ON journal_lines(cost_center_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_store_branch ON journal_lines(store_id, branch_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS accounting_settings (
        key TEXT PRIMARY KEY NOT NULL,
        account_id TEXT NOT NULL DEFAULT '',
        value TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS accounting_audit_log (
        id TEXT PRIMARY KEY NOT NULL,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL DEFAULT '',
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT NOT NULL DEFAULT '',
        details TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT ''
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_created ON accounting_audit_log(created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_entity ON accounting_audit_log(entity_type, entity_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_reference ON accounting_audit_log(reference_type, reference_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS app_logs (
        id TEXT PRIMARY KEY NOT NULL,
        created_at TEXT NOT NULL,
        level TEXT NOT NULL,
        area TEXT NOT NULL,
        action TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        session_id TEXT NOT NULL DEFAULT '',
        trace_id TEXT NOT NULL DEFAULT '',
        device_platform TEXT NOT NULL DEFAULT '',
        device_model TEXT NOT NULL DEFAULT '',
        app_version TEXT NOT NULL DEFAULT '',
        os_version TEXT NOT NULL DEFAULT '',
        stack_trace TEXT NOT NULL DEFAULT '',
        is_synced INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT NOT NULL DEFAULT '',
        created_by_source TEXT NOT NULL DEFAULT 'app',
        is_important INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_created_at ON app_logs(created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_level ON app_logs(level, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_area ON app_logs(area, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_synced ON app_logs(is_synced, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_user_store ON app_logs(user_id, store_id, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_trace ON app_logs(trace_id);');
    await _ensureColumn(
        'app_logs', 'is_important', 'INTEGER NOT NULL DEFAULT 0');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY NOT NULL,
        created_at TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        field_name TEXT NOT NULL DEFAULT '',
        old_value TEXT NOT NULL DEFAULT '',
        new_value TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        user_name TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        session_id TEXT NOT NULL DEFAULT '',
        trace_id TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        source_module TEXT NOT NULL DEFAULT '',
        is_important INTEGER NOT NULL DEFAULT 1
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_user_store ON audit_logs(user_id, store_id, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_branch ON audit_logs(branch_id, created_at);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS payment_accounts (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        account_id TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (type IN ('cash', 'bank', 'card', 'wallet', 'cheque', 'other')),
        CHECK (is_default IN (0, 1)),
        CHECK (is_active IN (0, 1))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_accounts_account ON payment_accounts(account_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_accounts_type ON payment_accounts(type, is_active);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_locations (
        id TEXT PRIMARY KEY NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        account_id TEXT NOT NULL,
        parent_id TEXT NOT NULL DEFAULT '',
        payment_account_id TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        allow_negative INTEGER NOT NULL DEFAULT 0,
        current_balance REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        CHECK (type IN ('main_vault', 'branch_vault', 'cash_drawer', 'bank', 'wallet', 'other')),
        CHECK (is_default IN (0, 1)),
        CHECK (is_active IN (0, 1)),
        CHECK (allow_negative IN (0, 1))
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_locations_code_active ON cash_locations(code) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_locations_type ON cash_locations(type, is_active);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_locations_account ON cash_locations(account_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_locations_parent ON cash_locations(parent_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_locations_store_branch ON cash_locations(store_id, branch_id);');
    await _ensureColumn(
        'cash_locations', 'device_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_locations_device ON cash_locations(device_id, branch_id, type);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_transfers (
        id TEXT PRIMARY KEY NOT NULL,
        transfer_no TEXT NOT NULL,
        transfer_date TEXT NOT NULL,
        from_location_id TEXT NOT NULL,
        to_location_id TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'posted',
        journal_entry_id TEXT NOT NULL DEFAULT '',
        reference_type TEXT NOT NULL DEFAULT 'cash_transfer',
        reference_id TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL DEFAULT '',
        approved_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (status IN ('draft', 'posted', 'void'))
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_transfers_no_active ON cash_transfers(transfer_no) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_transfers_date ON cash_transfers(transfer_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_transfers_locations ON cash_transfers(from_location_id, to_location_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_transfers_status ON cash_transfers(status, transfer_date);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_drawer_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        drawer_no TEXT NOT NULL,
        cash_location_id TEXT NOT NULL DEFAULT '',
        opened_at TEXT NOT NULL,
        closed_at TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'open',
        opening_balance REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        counted_cash REAL NOT NULL DEFAULT 0,
        difference REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        opened_by TEXT NOT NULL DEFAULT '',
        opened_by_user_id TEXT NOT NULL DEFAULT '',
        closed_by TEXT NOT NULL DEFAULT '',
        closed_by_user_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (status IN ('open', 'closed', 'void'))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_status ON cash_drawer_sessions(status, opened_at);');
    await _ensureColumn(
        'cash_drawer_sessions', 'cash_location_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('cash_drawer_sessions', 'opened_by_user_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('cash_drawer_sessions', 'closed_by_user_id',
        "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_location ON cash_drawer_sessions(cash_location_id, status);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_users ON cash_drawer_sessions(opened_by_user_id, closed_by_user_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cheques (
        id TEXT PRIMARY KEY NOT NULL,
        cheque_no TEXT NOT NULL,
        direction TEXT NOT NULL,
        party_type TEXT NOT NULL DEFAULT '',
        party_id TEXT NOT NULL DEFAULT '',
        party_name TEXT NOT NULL DEFAULT '',
        bank_name TEXT NOT NULL DEFAULT '',
        due_date TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        journal_entry_id TEXT NOT NULL DEFAULT '',
        settlement_entry_id TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (direction IN ('received', 'issued')),
        CHECK (status IN ('pending', 'cleared', 'bounced', 'void'))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cheques_status_due ON cheques(status, due_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cheques_party ON cheques(party_type, party_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS accounting_periods (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        closed_at TEXT NOT NULL DEFAULT '',
        closed_by TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (status IN ('open', 'closed', 'locked'))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_periods_dates ON accounting_periods(start_date, end_date, status);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cost_centers (
        id TEXT PRIMARY KEY NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (is_active IN (0, 1))
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cost_centers_code_active ON cost_centers(code) WHERE deleted_at = '';");

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS accounting_branches (
        id TEXT PRIMARY KEY NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        CHECK (is_active IN (0, 1))
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_accounting_branches_code_active ON accounting_branches(code) WHERE deleted_at = '';");

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS fixed_assets (
        id TEXT PRIMARY KEY NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        acquisition_date TEXT NOT NULL,
        purchase_value REAL NOT NULL DEFAULT 0,
        useful_life_months INTEGER NOT NULL DEFAULT 0,
        asset_account_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (purchase_value >= 0),
        CHECK (useful_life_months >= 0),
        CHECK (status IN ('active', 'disposed', 'inactive'))
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_code_active ON fixed_assets(code) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_fixed_assets_status ON fixed_assets(status, acquisition_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_fixed_assets_store_branch ON fixed_assets(store_id, branch_id);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS fixed_asset_depreciation (
        id TEXT PRIMARY KEY NOT NULL,
        asset_id TEXT NOT NULL,
        period_key TEXT NOT NULL,
        depreciation_date TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        accumulated_after REAL NOT NULL DEFAULT 0,
        book_value_after REAL NOT NULL DEFAULT 0,
        journal_entry_id TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        CHECK (amount >= 0)
      );
    ''');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_asset_depreciation_asset_period_active ON fixed_asset_depreciation(asset_id, period_key) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_fixed_asset_depreciation_asset_date ON fixed_asset_depreciation(asset_id, depreciation_date);');

    await _seedDefaultChartOfAccounts();
    await _seedAdvancedAccountingDefaults();
    await _migrateDefaultAccountingArabicLabels();
  }

  Future<void> _addColumnIfMissing(
      String table, String column, String definition) async {
    try {
      await customStatement(
          'ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // Column already exists on upgraded local databases.
    }
  }

  Future<void> _seedDefaultChartOfAccounts() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final accounts = <List<String>>[
      ['acc_assets', '1000', 'الأصول', 'asset', 'group', '', 'debit'],
      ['acc_cash', '1100', 'النقدية', 'asset', 'cash', 'acc_assets', 'debit'],
      [
        'acc_main_vault',
        '1110',
        'الخزنة الرئيسية',
        'asset',
        'cash_location',
        'acc_cash',
        'debit'
      ],
      [
        'acc_main_drawer',
        '1120',
        'درج النقد الرئيسي',
        'asset',
        'cash_location',
        'acc_cash',
        'debit'
      ],
      ['acc_bank', '1200', 'البنك', 'asset', 'bank', 'acc_assets', 'debit'],
      [
        'acc_main_bank',
        '1210',
        'البنك الرئيسي',
        'asset',
        'bank_location',
        'acc_bank',
        'debit'
      ],
      [
        'acc_customers',
        '1300',
        'العملاء / الذمم المدينة',
        'asset',
        'receivable',
        'acc_assets',
        'debit'
      ],
      [
        'acc_inventory',
        '1400',
        'المخزون',
        'asset',
        'inventory',
        'acc_assets',
        'debit'
      ],
      [
        'acc_fixed_assets',
        '1600',
        'الأصول الثابتة',
        'asset',
        'fixed_assets',
        'acc_assets',
        'debit'
      ],
      [
        'acc_accum_depreciation',
        '1690',
        'مجمع الإهلاك',
        'asset',
        'accumulated_depreciation',
        'acc_assets',
        'credit'
      ],
      [
        'acc_vat_input',
        '1500',
        'ضريبة المدخلات / ضريبة قابلة للاسترداد',
        'asset',
        'tax_input',
        'acc_assets',
        'debit'
      ],
      [
        'acc_liabilities',
        '2000',
        'الالتزامات',
        'liability',
        'group',
        '',
        'credit'
      ],
      [
        'acc_suppliers',
        '2100',
        'الموردون / الذمم الدائنة',
        'liability',
        'payable',
        'acc_liabilities',
        'credit'
      ],
      [
        'acc_vat_output',
        '2200',
        'ضريبة المخرجات / ضريبة مستحقة',
        'liability',
        'tax_payable',
        'acc_liabilities',
        'credit'
      ],
      ['acc_equity', '3000', 'حقوق الملكية', 'equity', 'group', '', 'credit'],
      [
        'acc_owner_capital',
        '3100',
        'رأس مال المالك',
        'equity',
        'capital',
        'acc_equity',
        'credit'
      ],
      ['acc_revenue', '4000', 'الإيرادات', 'revenue', 'group', '', 'credit'],
      [
        'acc_sales',
        '4100',
        'إيرادات المبيعات',
        'revenue',
        'sales',
        'acc_revenue',
        'credit'
      ],
      [
        'acc_cost_of_sales',
        '5000',
        'تكلفة المبيعات',
        'cost_of_sales',
        'group',
        '',
        'debit'
      ],
      [
        'acc_cogs',
        '5100',
        'تكلفة البضاعة المباعة',
        'cost_of_sales',
        'cogs',
        'acc_cost_of_sales',
        'debit'
      ],
      ['acc_expenses', '6000', 'المصروفات', 'expense', 'group', '', 'debit'],
      [
        'acc_general_expenses',
        '6100',
        'مصروفات عامة',
        'expense',
        'general',
        'acc_expenses',
        'debit'
      ],
      [
        'acc_cash_over_short',
        '6200',
        'زيادة / عجز النقدية',
        'expense',
        'cash_reconciliation',
        'acc_expenses',
        'debit'
      ],
      [
        'acc_depreciation_expense',
        '6300',
        'مصروف الإهلاك',
        'expense',
        'depreciation',
        'acc_expenses',
        'debit'
      ],
    ];

    for (final account in accounts) {
      await customInsert(
        r'''
        INSERT OR IGNORE INTO accounts
          (id, code, name, type, subtype, parent_id, normal_balance, currency, is_system, is_active, description, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(account[0]),
          Variable<String>(account[1]),
          Variable<String>(account[2]),
          Variable<String>(account[3]),
          Variable<String>(account[4]),
          Variable<String>(account[5]),
          Variable<String>(account[6]),
          const Variable<String>('USD'),
          const Variable<String>('حساب افتراضي أساسي للمحاسبة'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    final settings = <List<String>>[
      [
        'default_cash_account_id',
        'acc_cash',
        'الحساب الافتراضي للمقبوضات والمدفوعات النقدية'
      ],
      [
        'default_bank_account_id',
        'acc_bank',
        'الحساب الافتراضي لمقبوضات ومدفوعات البنك/البطاقة'
      ],
      [
        'default_customers_account_id',
        'acc_customers',
        'حساب الرقابة الافتراضي للذمم المدينة'
      ],
      [
        'default_suppliers_account_id',
        'acc_suppliers',
        'حساب الرقابة الافتراضي للذمم الدائنة'
      ],
      [
        'default_inventory_account_id',
        'acc_inventory',
        'حساب أصل المخزون الافتراضي'
      ],
      [
        'default_fixed_assets_account_id',
        'acc_fixed_assets',
        'حساب الأصول الثابتة الافتراضي'
      ],
      [
        'default_accumulated_depreciation_account_id',
        'acc_accum_depreciation',
        'حساب مجمع الإهلاك الافتراضي'
      ],
      [
        'default_depreciation_expense_account_id',
        'acc_depreciation_expense',
        'حساب مصروف الإهلاك الافتراضي'
      ],
      [
        'default_sales_account_id',
        'acc_sales',
        'حساب إيرادات المبيعات الافتراضي'
      ],
      [
        'default_cogs_account_id',
        'acc_cogs',
        'حساب تكلفة البضاعة المباعة الافتراضي'
      ],
      [
        'default_expense_account_id',
        'acc_general_expenses',
        'حساب المصروفات التشغيلية الافتراضي'
      ],
      [
        'default_cash_over_short_account_id',
        'acc_cash_over_short',
        'حساب زيادة/عجز النقدية الافتراضي'
      ],
      [
        'default_sales_tax_account_id',
        'acc_vat_output',
        'حساب ضريبة القيمة المضافة لفواتير المبيعات'
      ],
      [
        'default_purchase_tax_account_id',
        'acc_vat_input',
        'حساب ضريبة القيمة المضافة لفواتير المشتريات'
      ],
      [
        'default_tax_payable_account_id',
        'acc_vat_output',
        'حساب صافي الضريبة المستحقة الافتراضي'
      ],
      [
        'default_vat_rate_percent',
        '',
        'نسبة ضريبة القيمة المضافة الافتراضية للترحيل المحاسبي التلقائي'
      ],
      ['accounting_engine_version', '', 'إصدار بنية وبذور محرك المحاسبة'],
    ];

    for (final setting in settings) {
      await customInsert(
        r'''
        INSERT OR IGNORE INTO accounting_settings
          (key, account_id, value, description, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(setting[0]),
          Variable<String>(setting[1]),
          Variable<String>(setting[0] == 'accounting_engine_version'
              ? '6'
              : setting[0] == 'default_vat_rate_percent'
                  ? '0'
                  : ''),
          Variable<String>(setting[2]),
          Variable<String>(now),
        ],
      );
    }
  }

  Future<void> _seedAdvancedAccountingDefaults() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final paymentAccounts = <List<String>>[
      ['pa_cash', 'درج النقد', 'cash', 'acc_cash', '1'],
      ['pa_bank', 'البنك / البطاقة', 'bank', 'acc_bank', '1'],
    ];
    for (final account in paymentAccounts) {
      await customInsert(
        r'''
        INSERT OR IGNORE INTO payment_accounts
          (id, name, type, account_id, is_default, is_active, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(account[0]),
          Variable<String>(account[1]),
          Variable<String>(account[2]),
          Variable<String>(account[3]),
          Variable<int>(int.tryParse(account[4]) ?? 0),
          const Variable<String>('حساب دفع افتراضي للمحاسبة المتقدمة'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    final cashLocations = <List<String>>[
      [
        'cl_main_vault',
        'MAIN-VAULT',
        'الخزنة الرئيسية',
        'main_vault',
        'acc_main_vault',
        '',
        'pa_cash',
        '1'
      ],
      [
        'cl_main_drawer',
        'MAIN-DRAWER',
        'درج النقد الرئيسي',
        'cash_drawer',
        'acc_main_drawer',
        'cl_main_vault',
        'pa_cash',
        '1'
      ],
      [
        'cl_main_bank',
        'MAIN-BANK',
        'البنك الرئيسي',
        'bank',
        'acc_main_bank',
        '',
        'pa_bank',
        '1'
      ],
    ];
    for (final location in cashLocations) {
      await customInsert(
        r'''
        INSERT OR IGNORE INTO cash_locations
          (id, code, name, type, account_id, parent_id, payment_account_id, is_default, is_active,
           allow_negative, current_balance, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 0, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(location[0]),
          Variable<String>(location[1]),
          Variable<String>(location[2]),
          Variable<String>(location[3]),
          Variable<String>(location[4]),
          Variable<String>(location[5]),
          Variable<String>(location[6]),
          Variable<int>(int.tryParse(location[7]) ?? 0),
          const Variable<String>('موقع نقدي افتراضي لإدارة النقدية'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    await customUpdate(
      "UPDATE cash_locations SET account_id = 'acc_main_vault' WHERE id = 'cl_main_vault' AND account_id = 'acc_cash'",
    );
    await customUpdate(
      "UPDATE cash_locations SET account_id = 'acc_main_drawer' WHERE id = 'cl_main_drawer' AND account_id = 'acc_cash'",
    );
    await customUpdate(
      "UPDATE cash_locations SET account_id = 'acc_main_bank' WHERE id = 'cl_main_bank' AND account_id = 'acc_bank'",
    );
    await customUpdate(
      "UPDATE cash_drawer_sessions SET cash_location_id = 'cl_main_drawer' WHERE cash_location_id = ''",
    );

    await customInsert(
      r'''
      INSERT OR IGNORE INTO cost_centers
        (id, code, name, is_active, notes, created_at, updated_at)
      VALUES ('cc_main', 'MAIN', 'مركز التكلفة الرئيسي', 1, 'مركز التكلفة الافتراضي', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now)
      ],
    );
    await customInsert(
      r'''
      INSERT OR IGNORE INTO accounting_branches
        (id, code, name, is_active, notes, created_at, updated_at)
      VALUES ('br_main', 'MAIN', 'الفرع الرئيسي', 1, 'الفرع المحاسبي الافتراضي', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now)
      ],
    );
    await customInsert(
      r'''
      INSERT INTO accounting_settings (key, account_id, value, description, updated_at)
      VALUES ('accounting_engine_version', '', '7', 'إصدار بنية وبذور محرك المحاسبة', ?)
      ON CONFLICT(key) DO UPDATE SET value = '7', updated_at = excluded.updated_at
      ''',
      variables: <Variable<Object>>[Variable<String>(now)],
    );
  }

  Future<void> _migrateDefaultAccountingArabicLabels() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final accountNames = <List<String>>[
      ['acc_assets', 'الأصول'],
      ['acc_cash', 'النقدية'],
      ['acc_bank', 'البنك'],
      ['acc_customers', 'العملاء / الذمم المدينة'],
      ['acc_inventory', 'المخزون'],
      ['acc_fixed_assets', 'الأصول الثابتة'],
      ['acc_accum_depreciation', 'مجمع الإهلاك'],
      ['acc_vat_input', 'ضريبة المدخلات / ضريبة قابلة للاسترداد'],
      ['acc_liabilities', 'الالتزامات'],
      ['acc_suppliers', 'الموردون / الذمم الدائنة'],
      ['acc_vat_output', 'ضريبة المخرجات / ضريبة مستحقة'],
      ['acc_equity', 'حقوق الملكية'],
      ['acc_owner_capital', 'رأس مال المالك'],
      ['acc_revenue', 'الإيرادات'],
      ['acc_sales', 'إيرادات المبيعات'],
      ['acc_cost_of_sales', 'تكلفة المبيعات'],
      ['acc_cogs', 'تكلفة البضاعة المباعة'],
      ['acc_expenses', 'المصروفات'],
      ['acc_general_expenses', 'مصروفات عامة'],
      ['acc_cash_over_short', 'زيادة / عجز النقدية'],
      ['acc_depreciation_expense', 'مصروف الإهلاك'],
    ];
    for (final account in accountNames) {
      await customUpdate(
        'UPDATE accounts SET name = ?, description = ?, updated_at = ? WHERE id = ? AND is_system = 1',
        variables: <Variable<Object>>[
          Variable<String>(account[1]),
          const Variable<String>('حساب افتراضي أساسي للمحاسبة'),
          Variable<String>(now),
          Variable<String>(account[0]),
        ],
      );
    }
    final paymentAccounts = <List<String>>[
      ['pa_cash', 'درج النقد', 'حساب دفع افتراضي للمحاسبة المتقدمة'],
      ['pa_bank', 'البنك / البطاقة', 'حساب دفع افتراضي للمحاسبة المتقدمة'],
    ];
    for (final account in paymentAccounts) {
      await customUpdate(
        'UPDATE payment_accounts SET name = ?, notes = ?, updated_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<String>(account[1]),
          Variable<String>(account[2]),
          Variable<String>(now),
          Variable<String>(account[0]),
        ],
      );
    }
    await customUpdate(
      "UPDATE cost_centers SET name = 'مركز التكلفة الرئيسي', notes = 'مركز التكلفة الافتراضي', updated_at = ? WHERE id = 'cc_main'",
      variables: <Variable<Object>>[Variable<String>(now)],
    );
    await customUpdate(
      "UPDATE accounting_branches SET name = 'الفرع الرئيسي', notes = 'الفرع المحاسبي الافتراضي', updated_at = ? WHERE id = 'br_main'",
      variables: <Variable<Object>>[Variable<String>(now)],
    );
    await customUpdate(
      "UPDATE accounting_settings SET value = '7', description = 'إصدار بنية وبذور محرك المحاسبة', updated_at = ? WHERE key = 'accounting_engine_version'",
      variables: <Variable<Object>>[Variable<String>(now)],
    );
  }

  Future<void> _createBusinessEntityTable(String tableName) async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY NOT NULL,
        entity_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL DEFAULT 1,
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        sort_index INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_updated_at ON $tableName(updated_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_deleted_at ON $tableName(deleted_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_store_branch ON $tableName(store_id, branch_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_sort_index ON $tableName(sort_index);');
  }
}
