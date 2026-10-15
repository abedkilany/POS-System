part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods1 on VentioDriftDatabase {
  Future<void> _applyFoundationSchema() async {
    // Connection PRAGMAs are applied in beforeOpen. Keeping them out of this
    // idempotent schema routine is essential because backup restore invokes it
    // from an existing transaction, where SQLite forbids changing journal or
    // synchronous safety levels.

    await customStatement('''
      CREATE TABLE IF NOT EXISTS migration_meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await _metaValue('sqlite_foundation_version');

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
      'product_price_history',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'expenses',
      'purchases',
      'warehouses',
      'stock_movements',
      'warehouse_transfer_orders',
      'account_transactions',
      'catalog_categories',
      'catalog_brands',
      'catalog_units',
      'user_roles',
      'app_users',
    ]) {
      await _createBusinessEntityTable(tableName);
    }
    await _ensureWarehouseInventoryTable();
    await _ensureWarehouseTransferOrderColumns();
    await _ensureAssistantChatHistorySchema();
    await _ensureStockOperationsTable();
    await _ensureInventoryMigrationAdjustmentsTable();
    await _ensureInventoryReconciliationsTable();
    await _ensurePerformanceSupportTables();
    await _ensureOperationalBusinessColumns();
    await _ensureInventoryBatchTables();
    await _ensureSimpleBusinessColumns();
    await _ensureComplexBusinessColumns();
    await _ensureBusinessQueryIndexes();
    await _ensureIdentityBusinessColumns();
    await _ensureLastModifiedByDeviceIdColumns();

    await _createAccountingFoundation();

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

    await _normalizeProductCostRows();

    await customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        const Variable<String>('sqlite_foundation_version'),
        const Variable<String>('13'),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  Future<void> _sealLegacyAuditRows() async {
    final pending = await customSelect(
      "SELECT COUNT(*) AS row_count FROM audit_logs WHERE record_hash = ''",
    ).getSingle();
    final count = pending.read<int>('row_count');

    final triggerRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('trg_audit_logs_no_update', 'trg_audit_logs_no_delete')",
    ).get();
    if (count > 0 && triggerRows.isNotEmpty) {
      throw StateError(
        'Audit integrity failure: $count append-only audit row(s) are missing '
        'their integrity hash.',
      );
    }

    final rows = await customSelect(
      'SELECT * FROM audit_logs ORDER BY rowid ASC',
    ).get();
    var previousHash = '';
    for (final row in rows) {
      final data = row.data;
      final existingHash = data['record_hash']?.toString() ?? '';
      if (existingHash.isNotEmpty) {
        final expected = computeAuditRecordHashFromRow(
          data,
          previousHash: previousHash,
        );
        if (existingHash != expected ||
            (data['previous_hash']?.toString() ?? '') != previousHash) {
          throw StateError(
            'Audit integrity failure while sealing legacy rows.',
          );
        }
        previousHash = existingHash;
        continue;
      }
      final recordHash = computeAuditRecordHashFromRow(
        data,
        previousHash: previousHash,
      );
      await customUpdate(
        'UPDATE audit_logs SET previous_hash = ?, record_hash = ?, hash_version = 1 WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<String>(previousHash),
          Variable<String>(recordHash),
          Variable<String>(data['id']?.toString() ?? ''),
        ],
      );
      previousHash = recordHash;
    }
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

  Future<void> _rebuildVoucherTablesForDiscountOnlySettlements() async {
    final definitions = <String, Map<String, Object>>{
      'receipt_vouchers': <String, Object>{
        'create': r'''
          CREATE TABLE receipt_vouchers (
            id TEXT PRIMARY KEY NOT NULL,
            voucher_no TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            customer_name TEXT NOT NULL DEFAULT '',
            voucher_date TEXT NOT NULL,
            amount REAL NOT NULL,
            discount REAL NOT NULL DEFAULT 0,
            unallocated_amount REAL NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'USD',
            payment_method TEXT NOT NULL DEFAULT 'Cash',
            cash_location_id TEXT NOT NULL DEFAULT '',
            cash_drawer_session_id TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'posted',
            reversed_at TEXT NOT NULL DEFAULT '',
            reversal_reason TEXT NOT NULL DEFAULT '',
            reversed_by TEXT NOT NULL DEFAULT '',
            reversed_by_user_id TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_by TEXT NOT NULL DEFAULT '',
            created_by_user_id TEXT NOT NULL DEFAULT '',
            device_id TEXT NOT NULL DEFAULT '',
            branch_id TEXT NOT NULL DEFAULT '',
            store_id TEXT NOT NULL DEFAULT '',
            idempotency_key TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT NOT NULL DEFAULT '',
            sync_status TEXT NOT NULL DEFAULT 'pending',
            version INTEGER NOT NULL DEFAULT 1,
            last_modified_by_device_id TEXT NOT NULL DEFAULT '',
            CHECK (amount >= 0),
            CHECK (unallocated_amount >= 0 AND unallocated_amount <= amount),
            CHECK (status IN ('posted', 'reversed', 'void'))
          );
        ''',
        'indexes': <String>[
          'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_customer_date ON receipt_vouchers(customer_id, voucher_date DESC);',
          'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_session_date ON receipt_vouchers(cash_drawer_session_id, voucher_date DESC);',
          'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_store_branch_date ON receipt_vouchers(store_id, branch_id, voucher_date DESC);',
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_receipt_vouchers_idempotency ON receipt_vouchers(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';",
        ],
      },
      'payment_vouchers': <String, Object>{
        'create': r'''
          CREATE TABLE payment_vouchers (
            id TEXT PRIMARY KEY NOT NULL,
            voucher_no TEXT NOT NULL,
            supplier_id TEXT NOT NULL,
            supplier_name TEXT NOT NULL DEFAULT '',
            voucher_date TEXT NOT NULL,
            amount REAL NOT NULL,
            discount REAL NOT NULL DEFAULT 0,
            unallocated_amount REAL NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'USD',
            payment_method TEXT NOT NULL DEFAULT 'Cash',
            cash_location_id TEXT NOT NULL DEFAULT '',
            cash_drawer_session_id TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'posted',
            reversed_at TEXT NOT NULL DEFAULT '',
            reversal_reason TEXT NOT NULL DEFAULT '',
            reversed_by TEXT NOT NULL DEFAULT '',
            reversed_by_user_id TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_by TEXT NOT NULL DEFAULT '',
            created_by_user_id TEXT NOT NULL DEFAULT '',
            device_id TEXT NOT NULL DEFAULT '',
            branch_id TEXT NOT NULL DEFAULT '',
            store_id TEXT NOT NULL DEFAULT '',
            idempotency_key TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT NOT NULL DEFAULT '',
            sync_status TEXT NOT NULL DEFAULT 'pending',
            version INTEGER NOT NULL DEFAULT 1,
            last_modified_by_device_id TEXT NOT NULL DEFAULT '',
            CHECK (amount >= 0),
            CHECK (unallocated_amount >= 0 AND unallocated_amount <= amount),
            CHECK (status IN ('posted', 'reversed', 'void'))
          );
        ''',
        'indexes': <String>[
          'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_supplier_date ON payment_vouchers(supplier_id, voucher_date DESC);',
          'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_session_date ON payment_vouchers(cash_drawer_session_id, voucher_date DESC);',
          'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_store_branch_date ON payment_vouchers(store_id, branch_id, voucher_date DESC);',
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_vouchers_idempotency ON payment_vouchers(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';",
        ],
      },
      'payment_allocations': <String, Object>{
        'create': r'''
          CREATE TABLE payment_allocations (
            id TEXT PRIMARY KEY NOT NULL,
            voucher_type TEXT NOT NULL,
            voucher_id TEXT NOT NULL,
            reference_type TEXT NOT NULL,
            reference_id TEXT NOT NULL,
            reference_number TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL,
            reference_amount REAL NOT NULL,
            currency TEXT NOT NULL DEFAULT 'USD',
            reference_currency TEXT NOT NULL DEFAULT 'USD',
            exchange_rate REAL NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'active',
            allocation_kind TEXT NOT NULL DEFAULT 'allocation',
            reversal_of_id TEXT NOT NULL DEFAULT '',
            reversed_at TEXT NOT NULL DEFAULT '',
            reversal_reason TEXT NOT NULL DEFAULT '',
            reversed_by TEXT NOT NULL DEFAULT '',
            reversed_by_user_id TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT NOT NULL DEFAULT '',
            sync_status TEXT NOT NULL DEFAULT 'pending',
            version INTEGER NOT NULL DEFAULT 1,
            last_modified_by_device_id TEXT NOT NULL DEFAULT '',
            CHECK (voucher_type IN ('receipt', 'payment')),
            CHECK (reference_type IN ('sale', 'purchase')),
            CHECK (amount >= 0),
            CHECK (reference_amount > 0),
            CHECK (exchange_rate > 0)
          );
        ''',
        'indexes': <String>[
          'CREATE INDEX IF NOT EXISTS idx_payment_allocations_voucher ON payment_allocations(voucher_type, voucher_id);',
          'CREATE INDEX IF NOT EXISTS idx_payment_allocations_reference ON payment_allocations(reference_type, reference_id);',
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_allocations_target_per_voucher_kind_active ON payment_allocations(voucher_type, voucher_id, reference_type, reference_id, allocation_kind, reversal_of_id) WHERE deleted_at = '' AND status = 'active';",
          'CREATE INDEX IF NOT EXISTS idx_payment_allocations_status ON payment_allocations(status, reference_type, reference_id);',
        ],
      },
    };

    final needsRebuild = <String>[];
    for (final table in definitions.keys) {
      final row = await customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(table)],
      ).getSingleOrNull();
      final schema = row?.data['sql']?.toString() ?? '';
      if (schema
          .replaceAll(RegExp(r'\s+'), ' ')
          .contains('CHECK (amount > 0)')) {
        needsRebuild.add(table);
      }
    }
    if (needsRebuild.isEmpty) return;

    await customStatement('PRAGMA foreign_keys = OFF;');
    try {
      for (final table in needsRebuild) {
        final legacy = '${table}__legacy_discount_zero';
        await customStatement('DROP TABLE IF EXISTS $legacy;');
        await customStatement('ALTER TABLE $table RENAME TO $legacy;');
        final indexes = definitions[table]!['indexes']! as List<String>;
        for (final index in indexes) {
          final name =
              RegExp(r'INDEX IF NOT EXISTS\s+([^\s]+)', caseSensitive: false)
                  .firstMatch(index)
                  ?.group(1);
          if (name != null) {
            await customStatement('DROP INDEX IF EXISTS $name;');
          }
        }
      }
      for (final table in needsRebuild) {
        final definition = definitions[table]!;
        await customStatement(definition['create']! as String);
        final legacy = '${table}__legacy_discount_zero';
        final sourceColumns = await _tableColumns(legacy);
        final targetColumns = await _tableColumns(table);
        final columns =
            sourceColumns.where(targetColumns.contains).toList(growable: false);
        final joined = columns.join(', ');
        if (joined.isNotEmpty) {
          await customStatement('''
            INSERT INTO $table ($joined)
            SELECT $joined FROM $legacy;
          ''');
        }
        await customStatement('DROP TABLE $legacy;');
        for (final index in definition['indexes']! as List<String>) {
          await customStatement(index);
        }
      }
    } finally {
      await customStatement('PRAGMA foreign_keys = ON;');
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
      'product_price_history',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'expenses',
      'purchases',
      'warehouses',
      'stock_movements',
      'warehouse_transfer_orders',
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
      await _normalizeProductCostRows();
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
    await _ensureWarehouseInventoryColumns();
    await _ensureStockOperationsColumns();
    await _ensureCatalogColumns('catalog_categories');
    await _ensureCatalogColumns('catalog_brands');
    await _ensureCatalogColumns('catalog_units');
    await _ensurePriceListColumns();
    await _ensureProductPriceColumns();
    await _ensureProductPriceHistoryColumns();
    await _ensureProductPriceOverrideColumns();
    await _ensureProductCostColumns();
    await _ensureCostingMethodHistoryColumns();
    await _ensureInventoryCostLayerColumns();
    await _ensureSupplierProductPriceColumns();
    await _backfillSimpleBusinessColumnsIfNeeded();
  }

  Future<void> _normalizeProductCostRows() async {
    // ProductCost is one current snapshot per product. Retain the newest active
    // legacy row and make future writes enforce that invariant.
    await transaction(() async {
      await customStatement(r'''
        DELETE FROM product_costs
        WHERE deleted_at = ''
          AND trim(product_id) <> ''
          AND id IN (
            SELECT id FROM (
              SELECT id,
                     ROW_NUMBER() OVER (
                       PARTITION BY product_id
                       ORDER BY updated_at DESC, id DESC
                     ) AS rn
              FROM product_costs
              WHERE deleted_at = '' AND trim(product_id) <> ''
            ) ranked
            WHERE rn > 1
          );
      ''');
      await customStatement(r'''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_product_costs_product_active
        ON product_costs(product_id)
        WHERE deleted_at = '' AND trim(product_id) <> '';
      ''');
    });
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

  Future<void> _ensurePerformanceSupportTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS daily_metrics (
        metric_date TEXT PRIMARY KEY NOT NULL,
        sales_total REAL NOT NULL DEFAULT 0,
        sales_profit REAL NOT NULL DEFAULT 0,
        sales_count INTEGER NOT NULL DEFAULT 0,
        purchases_total REAL NOT NULL DEFAULT 0,
        expenses_total REAL NOT NULL DEFAULT 0,
        stock_in REAL NOT NULL DEFAULT 0,
        stock_out REAL NOT NULL DEFAULT 0,
        cash_in REAL NOT NULL DEFAULT 0,
        cash_out REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_daily_metrics_date ON daily_metrics(metric_date);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS search_index (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        search_text TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_search_index_type_text ON search_index(entity_type, search_text);');

    try {
      await customStatement(r'''
        CREATE VIRTUAL TABLE IF NOT EXISTS search_index_fts
        USING fts5(entity_type UNINDEXED, entity_id UNINDEXED, search_text);
      ''');
    } catch (_) {
      // Some SQLite builds may omit FTS5; search_index remains the fallback.
    }
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
      'product_price_history',
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
}
