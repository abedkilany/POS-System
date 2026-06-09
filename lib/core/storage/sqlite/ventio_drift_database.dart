import 'package:drift/drift.dart';

import 'sqlite_database_connection.dart';

/// Drift-backed SQLite foundation for Ventio.
///
/// Phase 3 keeps SQLite as the authoritative local store. Hive is retained only
/// as a one-time safety backup source for devices upgrading from older builds.
/// The tables below track migration progress, sync state, and the app key/value
/// data that previously lived in Hive.
class VentioDriftDatabase extends GeneratedDatabase {
  VentioDriftDatabase([QueryExecutor? executor]) : super(executor ?? openVentioSqliteConnection());

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const <DatabaseSchemaEntity>[];

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
        hive_backup_json TEXT,
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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_local_key_values_updated_at ON local_key_values(updated_at);');


    await customStatement('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await customStatement('CREATE INDEX IF NOT EXISTS idx_settings_updated_at ON settings(updated_at);');

    await _createBusinessEntityTable('products');
    await _createBusinessEntityTable('customers');
    await _createBusinessEntityTable('suppliers');
    await _createBusinessEntityTable('sales');
    await _createBusinessEntityTable('supplier_product_prices');
    await _createBusinessEntityTable('expenses');
    await _createBusinessEntityTable('purchases');
    await _createBusinessEntityTable('stock_movements');
    await _createBusinessEntityTable('account_transactions');
    await _createBusinessEntityTable('catalog_categories');
    await _createBusinessEntityTable('catalog_brands');
    await _createBusinessEntityTable('catalog_units');
    await _createBusinessEntityTable('user_roles');
    await _createBusinessEntityTable('app_users');

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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_events_sequence ON sync_events(sequence, created_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_events_entity ON sync_events(entity_type, entity_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_events_synced ON sync_events(is_synced, sequence);');

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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_pending_sync_changes_event ON pending_sync_changes(event_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pending_sync_changes_sequence ON pending_sync_changes(sequence, created_at);');

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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status, next_retry_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_queue_change ON sync_queue(change_id);');

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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity ON sync_conflicts(entity_type, entity_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_conflicts_resolution ON sync_conflicts(resolution, created_at);');

    await customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        const Variable<String>('sqlite_foundation_version'),
        const Variable<String>('4'),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }


  Future<void> _createBusinessEntityTable(String tableName) async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY NOT NULL,
        entity_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL DEFAULT 1,
        sort_index INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_${tableName}_updated_at ON $tableName(updated_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_${tableName}_deleted_at ON $tableName(deleted_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_${tableName}_store_branch ON $tableName(store_id, branch_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_${tableName}_sort_index ON $tableName(sort_index);');
  }
}
