part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods3 on VentioDriftDatabase {
  Future<void> _ensureWarehouseInventoryColumns() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS warehouse_inventory (
        id TEXT PRIMARY KEY NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        warehouse_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        UNIQUE(store_id, warehouse_id, product_id)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_inventory_store_warehouse_product ON warehouse_inventory(store_id, warehouse_id, product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_inventory_store_product_quantity ON warehouse_inventory(store_id, product_id, quantity);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_inventory_product ON warehouse_inventory(product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_inventory_warehouse ON warehouse_inventory(warehouse_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_inventory_updated_at ON warehouse_inventory(updated_at);');
  }

  Future<void> _ensureInventoryBatchTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_batches (
        id TEXT PRIMARY KEY NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL DEFAULT '',
        supplier_batch_number TEXT NOT NULL DEFAULT '',
        manufacturing_date TEXT NOT NULL DEFAULT '',
        expiration_date TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        source_type TEXT NOT NULL DEFAULT '',
        source_id TEXT NOT NULL DEFAULT '',
        source_line_id TEXT NOT NULL DEFAULT '',
        unit_cost REAL NOT NULL DEFAULT 0,
        initial_quantity REAL NOT NULL DEFAULT 0,
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        exchange_rate REAL NOT NULL DEFAULT 1,
        received_at TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (product_id) REFERENCES products(id),
        CHECK (status IN ('active', 'blocked', 'depleted', 'disposed')),
        CHECK (unit_cost >= 0),
        CHECK (initial_quantity >= 0),
        CHECK (exchange_rate > 0)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_product_expiry ON inventory_batches(product_id, expiration_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_store_status_expiry ON inventory_batches(store_id, status, expiration_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_supplier_number ON inventory_batches(supplier_batch_number);');
    await _ensureColumn(
        'inventory_batches', 'source_line_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_batches', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'inventory_batches', 'initial_quantity', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'inventory_batches', 'cost_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'inventory_batches', 'exchange_rate', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'inventory_batches', 'received_at', "TEXT NOT NULL DEFAULT ''");
    await customStatement('''
      UPDATE inventory_batches
      SET received_at = created_at
      WHERE trim(received_at) = '';
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_source_line ON inventory_batches(source_type, source_id, source_line_id);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_inventory_batches_source_line ON inventory_batches(store_id, source_type, source_id, source_line_id) WHERE trim(source_line_id) <> ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_received_at ON inventory_batches(product_id, received_at, id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS unified_batch_cutovers (
        id TEXT PRIMARY KEY NOT NULL,
        store_id TEXT NOT NULL,
        warehouse_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        cutover_at TEXT NOT NULL,
        opening_batch_id TEXT NOT NULL DEFAULT '',
        opening_quantity REAL NOT NULL DEFAULT 0,
        opening_unit_cost REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        UNIQUE(store_id, warehouse_id, product_id),
        CHECK (opening_quantity >= 0),
        CHECK (opening_unit_cost >= 0)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_unified_batch_cutovers_product ON unified_batch_cutovers(store_id, warehouse_id, product_id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_batch_balances (
        id TEXT PRIMARY KEY NOT NULL,
        batch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        warehouse_id TEXT NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        quantity REAL NOT NULL DEFAULT 0,
        reserved_quantity REAL NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (batch_id) REFERENCES inventory_batches(id),
        FOREIGN KEY (product_id) REFERENCES products(id),
        UNIQUE(store_id, warehouse_id, product_id, batch_id),
        CHECK (quantity >= 0),
        CHECK (reserved_quantity >= 0)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_batch_balances_fefo ON inventory_batch_balances(store_id, warehouse_id, product_id, quantity);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_batch_balances_batch ON inventory_batch_balances(batch_id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_stock_deficits (
        id TEXT PRIMARY KEY NOT NULL,
        deficit_batch_id TEXT NOT NULL UNIQUE,
        product_id TEXT NOT NULL,
        warehouse_id TEXT NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        quantity_original REAL NOT NULL,
        quantity_open REAL NOT NULL,
        provisional_unit_cost REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (deficit_batch_id) REFERENCES inventory_batches(id),
        FOREIGN KEY (product_id) REFERENCES products(id),
        CHECK (quantity_original > 0),
        CHECK (quantity_open >= 0),
        CHECK (quantity_open <= quantity_original + 0.000001),
        CHECK (provisional_unit_cost >= 0),
        CHECK (status IN ('open', 'resolved', 'reversed'))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_stock_deficits_open ON inventory_stock_deficits(store_id, warehouse_id, product_id, status, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_stock_deficits_batch ON inventory_stock_deficits(deficit_batch_id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_deficit_settlements (
        id TEXT PRIMARY KEY NOT NULL,
        deficit_id TEXT NOT NULL,
        incoming_batch_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        reversed_quantity REAL NOT NULL DEFAULT 0,
        provisional_unit_cost REAL NOT NULL DEFAULT 0,
        actual_unit_cost REAL NOT NULL DEFAULT 0,
        cost_adjustment REAL NOT NULL DEFAULT 0,
        settled_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        FOREIGN KEY (deficit_id) REFERENCES inventory_stock_deficits(id),
        FOREIGN KEY (incoming_batch_id) REFERENCES inventory_batches(id),
        CHECK (quantity > 0),
        CHECK (reversed_quantity >= 0),
        CHECK (reversed_quantity <= quantity + 0.000001),
        CHECK (provisional_unit_cost >= 0),
        CHECK (actual_unit_cost >= 0),
        CHECK (status IN ('active', 'partial_reversal', 'reversed'))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_deficit_settlements_deficit ON inventory_deficit_settlements(deficit_id, settled_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_deficit_settlements_batch ON inventory_deficit_settlements(incoming_batch_id);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS purchase_item_batch_allocations (
        id TEXT PRIMARY KEY NOT NULL,
        purchase_item_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        batch_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        supplier_batch_number TEXT NOT NULL DEFAULT '',
        manufacturing_date TEXT NOT NULL DEFAULT '',
        expiration_date TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES inventory_batches(id),
        CHECK (quantity > 0)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_batch_allocations_item ON purchase_item_batch_allocations(purchase_item_id, line_no);');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sale_item_batch_allocations (
        id TEXT PRIMARY KEY NOT NULL,
        sale_item_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        batch_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL NOT NULL DEFAULT 0,
        expiration_date TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES inventory_batches(id),
        CHECK (quantity > 0)
      );
    ''');
    await _ensureColumn(
        'sale_item_batch_allocations', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_batch_allocations_item ON sale_item_batch_allocations(sale_item_id, line_no);');

    await _ensureColumn(
        'stock_movements', 'batch_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_cost_layers', 'batch_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_batch_date ON stock_movements(batch_id, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference_type_batch ON stock_movements(store_id, reference_id, movement_type, batch_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_batches_source_trace ON inventory_batches(store_id, source_type, source_id, id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_cost_layers_batch ON inventory_cost_layers(batch_id);');
  }

  Future<void> _ensureStockOperationsTable() async {
    await _ensureStockOperationsColumns();
  }

  Future<void> _ensureStockOperationsColumns() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS stock_operations (
        id TEXT PRIMARY KEY NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        operation_type TEXT NOT NULL,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        movement_group_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        started_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT '',
        completed_at TEXT NOT NULL DEFAULT '',
        failure_reason TEXT NOT NULL DEFAULT '',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        device_id TEXT NOT NULL DEFAULT '',
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        UNIQUE(store_id, idempotency_key)
      );
    ''');
    await _ensureColumn(
        'stock_operations', 'started_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_operations', 'updated_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_operations', 'failure_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_operations', 'attempt_count', 'INTEGER NOT NULL DEFAULT 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_operations_document ON stock_operations(store_id, document_type, document_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_operations_group ON stock_operations(movement_group_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_operations_status ON stock_operations(status, created_at);');
  }

  Future<void> _ensureInventoryReconciliationsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_reconciliations (
        id TEXT PRIMARY KEY NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        warehouse_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        legacy_product_stock REAL NOT NULL DEFAULT 0,
        ledger_balance REAL NOT NULL DEFAULT 0,
        warehouse_balance REAL NOT NULL DEFAULT 0,
        difference REAL NOT NULL DEFAULT 0,
        classification TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        resolved_at TEXT NOT NULL DEFAULT '',
        resolution_note TEXT NOT NULL DEFAULT '',
        UNIQUE(store_id, warehouse_id, product_id)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_reconciliations_store_status ON inventory_reconciliations(store_id, status, classification);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_reconciliations_product ON inventory_reconciliations(product_id);');
  }

  Future<void> _ensureInventoryMigrationAdjustmentsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_migration_adjustments (
        id TEXT PRIMARY KEY NOT NULL,
        migration_batch_id TEXT NOT NULL,
        store_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT 'main',
        warehouse_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        legacy_product_stock REAL NOT NULL DEFAULT 0,
        ledger_balance REAL NOT NULL DEFAULT 0,
        applied_delta REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        UNIQUE(migration_batch_id, store_id, warehouse_id, product_id)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_migration_adjustments_batch ON inventory_migration_adjustments(migration_batch_id, store_id, warehouse_id, product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_migration_adjustments_store ON inventory_migration_adjustments(store_id, product_id);');
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

  Future<void> _ensureProductPriceHistoryColumns() async {
    await _ensureColumn(
        'product_price_history', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_price_history', 'price_list_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_price_history', 'unit_id', "TEXT NOT NULL DEFAULT 'base'");
    await _ensureColumn('product_price_history', 'currency_code',
        "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'product_price_history', 'old_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_price_history', 'new_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'product_price_history', 'change_percent', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('product_price_history', 'change_type',
        "TEXT NOT NULL DEFAULT 'manual'");
    await _ensureColumn(
        'product_price_history', 'source', "TEXT NOT NULL DEFAULT 'manual'");
    await _ensureColumn(
        'product_price_history', 'batch_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_price_history', 'user_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_price_history', 'user_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'product_price_history', 'changed_at', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_price_history_product_changed ON product_price_history(product_id, changed_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_price_history_batch ON product_price_history(batch_id);');
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
}
