import 'package:drift/drift.dart';

import 'sqlite_database_connection.dart';

/// Drift-backed SQLite foundation for Ventio.
///
/// Phase 3 keeps SQLite as the authoritative local store. legacy JSON storage is retained only
/// as a one-time safety backup source for devices upgrading from older builds.
/// The tables below track migration progress, sync state, and the app key/value
/// data that previously lived in legacy JSON storage.
class VentioDriftDatabase extends GeneratedDatabase {
  VentioDriftDatabase([QueryExecutor? executor]) : super(executor ?? openVentioSqliteConnection());

  @override
  int get schemaVersion => 6;

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

    await _createAccountingFoundation();

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
        const Variable<String>('5'),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
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

    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_active ON accounts(code) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts(type, subtype);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounts_parent ON accounts(parent_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounts_store_branch ON accounts(store_id, branch_id);');

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

    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_entry_no_active ON journal_entries(entry_no) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON journal_entries(reference_type, reference_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON journal_entries(status, entry_date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_entries_store_branch ON journal_entries(store_id, branch_id);');

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

    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(entry_id, line_no);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);');
    await _addColumnIfMissing('journal_lines', 'cost_center_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_lines_party ON journal_lines(party_type, party_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_lines_cost_center ON journal_lines(cost_center_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_lines_store_branch ON journal_lines(store_id, branch_id);');

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
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_created ON accounting_audit_log(created_at);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_entity ON accounting_audit_log(entity_type, entity_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounting_audit_log_reference ON accounting_audit_log(reference_type, reference_id);');

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
    await customStatement('CREATE INDEX IF NOT EXISTS idx_payment_accounts_account ON payment_accounts(account_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_payment_accounts_type ON payment_accounts(type, is_active);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_drawer_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        drawer_no TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'open',
        opening_balance REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        counted_cash REAL NOT NULL DEFAULT 0,
        difference REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        opened_by TEXT NOT NULL DEFAULT '',
        closed_by TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (status IN ('open', 'closed', 'void'))
      );
    ''');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_status ON cash_drawer_sessions(status, opened_at);');

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
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cheques_status_due ON cheques(status, due_date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cheques_party ON cheques(party_type, party_id);');

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
    await customStatement('CREATE INDEX IF NOT EXISTS idx_accounting_periods_dates ON accounting_periods(start_date, end_date, status);');

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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_cost_centers_code_active ON cost_centers(code) WHERE deleted_at = '';");

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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounting_branches_code_active ON accounting_branches(code) WHERE deleted_at = '';");

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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_code_active ON fixed_assets(code) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_fixed_assets_status ON fixed_assets(status, acquisition_date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_fixed_assets_store_branch ON fixed_assets(store_id, branch_id);');


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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_asset_depreciation_asset_period_active ON fixed_asset_depreciation(asset_id, period_key) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_fixed_asset_depreciation_asset_date ON fixed_asset_depreciation(asset_id, depreciation_date);');

    await _seedDefaultChartOfAccounts();
    await _seedAdvancedAccountingDefaults();
  }

  Future<void> _addColumnIfMissing(String table, String column, String definition) async {
    try {
      await customStatement('ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // Column already exists on upgraded local databases.
    }
  }

  Future<void> _seedDefaultChartOfAccounts() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final accounts = <List<String>>[
      ['acc_assets', '1000', 'Assets', 'asset', 'group', '', 'debit'],
      ['acc_cash', '1100', 'Cash', 'asset', 'cash', 'acc_assets', 'debit'],
      ['acc_bank', '1200', 'Bank', 'asset', 'bank', 'acc_assets', 'debit'],
      ['acc_customers', '1300', 'Customers / Accounts Receivable', 'asset', 'receivable', 'acc_assets', 'debit'],
      ['acc_inventory', '1400', 'Inventory', 'asset', 'inventory', 'acc_assets', 'debit'],
      ['acc_fixed_assets', '1600', 'Fixed Assets', 'asset', 'fixed_assets', 'acc_assets', 'debit'],
      ['acc_accum_depreciation', '1690', 'Accumulated Depreciation', 'asset', 'accumulated_depreciation', 'acc_assets', 'credit'],
      ['acc_vat_input', '1500', 'VAT Input / Recoverable Tax', 'asset', 'tax_input', 'acc_assets', 'debit'],
      ['acc_liabilities', '2000', 'Liabilities', 'liability', 'group', '', 'credit'],
      ['acc_suppliers', '2100', 'Suppliers / Accounts Payable', 'liability', 'payable', 'acc_liabilities', 'credit'],
      ['acc_vat_output', '2200', 'VAT Output / Tax Payable', 'liability', 'tax_payable', 'acc_liabilities', 'credit'],
      ['acc_equity', '3000', 'Equity', 'equity', 'group', '', 'credit'],
      ['acc_owner_capital', '3100', 'Owner Capital', 'equity', 'capital', 'acc_equity', 'credit'],
      ['acc_revenue', '4000', 'Revenue', 'revenue', 'group', '', 'credit'],
      ['acc_sales', '4100', 'Sales Revenue', 'revenue', 'sales', 'acc_revenue', 'credit'],
      ['acc_cost_of_sales', '5000', 'Cost of Sales', 'cost_of_sales', 'group', '', 'debit'],
      ['acc_cogs', '5100', 'Cost of Goods Sold', 'cost_of_sales', 'cogs', 'acc_cost_of_sales', 'debit'],
      ['acc_expenses', '6000', 'Expenses', 'expense', 'group', '', 'debit'],
      ['acc_general_expenses', '6100', 'General Expenses', 'expense', 'general', 'acc_expenses', 'debit'],
      ['acc_cash_over_short', '6200', 'Cash Over / Short', 'expense', 'cash_reconciliation', 'acc_expenses', 'debit'],
      ['acc_depreciation_expense', '6300', 'Depreciation Expense', 'expense', 'depreciation', 'acc_expenses', 'debit'],
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
          const Variable<String>('Default accounting foundation account'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    final settings = <List<String>>[
      ['default_cash_account_id', 'acc_cash', 'Default account for cash receipts and payments'],
      ['default_bank_account_id', 'acc_bank', 'Default account for bank/card receipts and payments'],
      ['default_customers_account_id', 'acc_customers', 'Default accounts receivable control account'],
      ['default_suppliers_account_id', 'acc_suppliers', 'Default accounts payable control account'],
      ['default_inventory_account_id', 'acc_inventory', 'Default inventory asset account'],
      ['default_fixed_assets_account_id', 'acc_fixed_assets', 'Default fixed assets account'],
      ['default_accumulated_depreciation_account_id', 'acc_accum_depreciation', 'Default accumulated depreciation contra-asset account'],
      ['default_depreciation_expense_account_id', 'acc_depreciation_expense', 'Default depreciation expense account'],
      ['default_sales_account_id', 'acc_sales', 'Default sales revenue account'],
      ['default_cogs_account_id', 'acc_cogs', 'Default cost of goods sold account'],
      ['default_expense_account_id', 'acc_general_expenses', 'Default operating expense account'],
      ['default_cash_over_short_account_id', 'acc_cash_over_short', 'Default cash reconciliation over/short account'],
      ['default_sales_tax_account_id', 'acc_vat_output', 'Default VAT/tax account for sales invoices'],
      ['default_purchase_tax_account_id', 'acc_vat_input', 'Default VAT/tax account for purchase invoices'],
      ['default_tax_payable_account_id', 'acc_vat_output', 'Default net tax payable account'],
      ['default_vat_rate_percent', '', 'Default VAT rate percent used by accounting auto-posting'],
      ['accounting_engine_version', '', 'Accounting engine schema/seed version'],
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
          Variable<String>(setting[0] == 'accounting_engine_version' ? '6' : setting[0] == 'default_vat_rate_percent' ? '0' : ''),
          Variable<String>(setting[2]),
          Variable<String>(now),
        ],
      );
    }
  }



  Future<void> _seedAdvancedAccountingDefaults() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final paymentAccounts = <List<String>>[
      ['pa_cash', 'Cash Drawer', 'cash', 'acc_cash', '1'],
      ['pa_bank', 'Bank / Card', 'bank', 'acc_bank', '1'],
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
          const Variable<String>('Default payment account for advanced accounting'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    await customInsert(
      r'''
      INSERT OR IGNORE INTO cost_centers
        (id, code, name, is_active, notes, created_at, updated_at)
      VALUES ('cc_main', 'MAIN', 'Main Cost Center', 1, 'Default cost center', ?, ?)
      ''',
      variables: <Variable<Object>>[Variable<String>(now), Variable<String>(now)],
    );
    await customInsert(
      r'''
      INSERT OR IGNORE INTO accounting_branches
        (id, code, name, is_active, notes, created_at, updated_at)
      VALUES ('br_main', 'MAIN', 'Main Branch', 1, 'Default accounting branch', ?, ?)
      ''',
      variables: <Variable<Object>>[Variable<String>(now), Variable<String>(now)],
    );
    await customInsert(
      r'''
      INSERT INTO accounting_settings (key, account_id, value, description, updated_at)
      VALUES ('accounting_engine_version', '', '3', 'Accounting engine schema/seed version', ?)
      ON CONFLICT(key) DO UPDATE SET value = '3', updated_at = excluded.updated_at
      ''',
      variables: <Variable<Object>>[Variable<String>(now)],
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
