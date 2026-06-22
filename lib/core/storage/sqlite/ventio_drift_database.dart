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
  int get schemaVersion => 8;

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


  Future<void> _ensureColumn(String tableName, String columnName, String definition) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    final exists = rows.any((row) => row.data['name']?.toString() == columnName);
    if (!exists) {
      await customStatement('ALTER TABLE $tableName ADD COLUMN $columnName $definition;');
    }
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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_locations_code_active ON cash_locations(code) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_locations_type ON cash_locations(type, is_active);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_locations_account ON cash_locations(account_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_locations_parent ON cash_locations(parent_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_locations_store_branch ON cash_locations(store_id, branch_id);');

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
    await customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_transfers_no_active ON cash_transfers(transfer_no) WHERE deleted_at = '';");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_transfers_date ON cash_transfers(transfer_date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_transfers_locations ON cash_transfers(from_location_id, to_location_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_transfers_status ON cash_transfers(status, transfer_date);');

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
        closed_by TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        CHECK (status IN ('open', 'closed', 'void'))
      );
    ''');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_status ON cash_drawer_sessions(status, opened_at);');
    await _ensureColumn('cash_drawer_sessions', 'cash_location_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement('CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_location ON cash_drawer_sessions(cash_location_id, status);');

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
    await _migrateDefaultAccountingArabicLabels();
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
      ['acc_assets', '1000', 'الأصول', 'asset', 'group', '', 'debit'],
      ['acc_cash', '1100', 'النقدية', 'asset', 'cash', 'acc_assets', 'debit'],
      ['acc_main_vault', '1110', 'الخزنة الرئيسية', 'asset', 'cash_location', 'acc_cash', 'debit'],
      ['acc_main_drawer', '1120', 'درج النقد الرئيسي', 'asset', 'cash_location', 'acc_cash', 'debit'],
      ['acc_bank', '1200', 'البنك', 'asset', 'bank', 'acc_assets', 'debit'],
      ['acc_main_bank', '1210', 'البنك الرئيسي', 'asset', 'bank_location', 'acc_bank', 'debit'],
      ['acc_customers', '1300', 'العملاء / الذمم المدينة', 'asset', 'receivable', 'acc_assets', 'debit'],
      ['acc_inventory', '1400', 'المخزون', 'asset', 'inventory', 'acc_assets', 'debit'],
      ['acc_fixed_assets', '1600', 'الأصول الثابتة', 'asset', 'fixed_assets', 'acc_assets', 'debit'],
      ['acc_accum_depreciation', '1690', 'مجمع الإهلاك', 'asset', 'accumulated_depreciation', 'acc_assets', 'credit'],
      ['acc_vat_input', '1500', 'ضريبة المدخلات / ضريبة قابلة للاسترداد', 'asset', 'tax_input', 'acc_assets', 'debit'],
      ['acc_liabilities', '2000', 'الالتزامات', 'liability', 'group', '', 'credit'],
      ['acc_suppliers', '2100', 'الموردون / الذمم الدائنة', 'liability', 'payable', 'acc_liabilities', 'credit'],
      ['acc_vat_output', '2200', 'ضريبة المخرجات / ضريبة مستحقة', 'liability', 'tax_payable', 'acc_liabilities', 'credit'],
      ['acc_equity', '3000', 'حقوق الملكية', 'equity', 'group', '', 'credit'],
      ['acc_owner_capital', '3100', 'رأس مال المالك', 'equity', 'capital', 'acc_equity', 'credit'],
      ['acc_revenue', '4000', 'الإيرادات', 'revenue', 'group', '', 'credit'],
      ['acc_sales', '4100', 'إيرادات المبيعات', 'revenue', 'sales', 'acc_revenue', 'credit'],
      ['acc_cost_of_sales', '5000', 'تكلفة المبيعات', 'cost_of_sales', 'group', '', 'debit'],
      ['acc_cogs', '5100', 'تكلفة البضاعة المباعة', 'cost_of_sales', 'cogs', 'acc_cost_of_sales', 'debit'],
      ['acc_expenses', '6000', 'المصروفات', 'expense', 'group', '', 'debit'],
      ['acc_general_expenses', '6100', 'مصروفات عامة', 'expense', 'general', 'acc_expenses', 'debit'],
      ['acc_cash_over_short', '6200', 'زيادة / عجز النقدية', 'expense', 'cash_reconciliation', 'acc_expenses', 'debit'],
      ['acc_depreciation_expense', '6300', 'مصروف الإهلاك', 'expense', 'depreciation', 'acc_expenses', 'debit'],
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
      ['default_cash_account_id', 'acc_cash', 'الحساب الافتراضي للمقبوضات والمدفوعات النقدية'],
      ['default_bank_account_id', 'acc_bank', 'الحساب الافتراضي لمقبوضات ومدفوعات البنك/البطاقة'],
      ['default_customers_account_id', 'acc_customers', 'حساب الرقابة الافتراضي للذمم المدينة'],
      ['default_suppliers_account_id', 'acc_suppliers', 'حساب الرقابة الافتراضي للذمم الدائنة'],
      ['default_inventory_account_id', 'acc_inventory', 'حساب أصل المخزون الافتراضي'],
      ['default_fixed_assets_account_id', 'acc_fixed_assets', 'حساب الأصول الثابتة الافتراضي'],
      ['default_accumulated_depreciation_account_id', 'acc_accum_depreciation', 'حساب مجمع الإهلاك الافتراضي'],
      ['default_depreciation_expense_account_id', 'acc_depreciation_expense', 'حساب مصروف الإهلاك الافتراضي'],
      ['default_sales_account_id', 'acc_sales', 'حساب إيرادات المبيعات الافتراضي'],
      ['default_cogs_account_id', 'acc_cogs', 'حساب تكلفة البضاعة المباعة الافتراضي'],
      ['default_expense_account_id', 'acc_general_expenses', 'حساب المصروفات التشغيلية الافتراضي'],
      ['default_cash_over_short_account_id', 'acc_cash_over_short', 'حساب زيادة/عجز النقدية الافتراضي'],
      ['default_sales_tax_account_id', 'acc_vat_output', 'حساب ضريبة القيمة المضافة لفواتير المبيعات'],
      ['default_purchase_tax_account_id', 'acc_vat_input', 'حساب ضريبة القيمة المضافة لفواتير المشتريات'],
      ['default_tax_payable_account_id', 'acc_vat_output', 'حساب صافي الضريبة المستحقة الافتراضي'],
      ['default_vat_rate_percent', '', 'نسبة ضريبة القيمة المضافة الافتراضية للترحيل المحاسبي التلقائي'],
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
      ['cl_main_vault', 'MAIN-VAULT', 'الخزنة الرئيسية', 'main_vault', 'acc_main_vault', '', 'pa_cash', '1'],
      ['cl_main_drawer', 'MAIN-DRAWER', 'درج النقد الرئيسي', 'cash_drawer', 'acc_main_drawer', 'cl_main_vault', 'pa_cash', '1'],
      ['cl_main_bank', 'MAIN-BANK', 'البنك الرئيسي', 'bank', 'acc_main_bank', '', 'pa_bank', '1'],
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
      variables: <Variable<Object>>[Variable<String>(now), Variable<String>(now)],
    );
    await customInsert(
      r'''
      INSERT OR IGNORE INTO accounting_branches
        (id, code, name, is_active, notes, created_at, updated_at)
      VALUES ('br_main', 'MAIN', 'الفرع الرئيسي', 1, 'الفرع المحاسبي الافتراضي', ?, ?)
      ''',
      variables: <Variable<Object>>[Variable<String>(now), Variable<String>(now)],
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
