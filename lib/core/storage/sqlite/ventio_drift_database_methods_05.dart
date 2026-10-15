part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods5 on VentioDriftDatabase {
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
        is_postable INTEGER NOT NULL DEFAULT 1,
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
        CHECK (is_postable IN (0, 1)),
        CHECK (is_active IN (0, 1))
      );
    ''');

    await _addColumnIfMissing(
        'accounts', 'is_postable', 'INTEGER NOT NULL DEFAULT 1');

    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_active ON accounts(code) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounts_postable ON accounts(is_postable, is_active);');
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

    await _addColumnIfMissing(
        'journal_entries', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        'journal_entries', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        'journal_entries', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        'journal_entries', 'reversed_by_entry_id', "TEXT NOT NULL DEFAULT ''");

    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_entry_no_active ON journal_entries(entry_no) WHERE deleted_at = '';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_accounting_entries_date ON journal_entries(entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON journal_entries(reference_type, reference_id);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_voucher_reference_active ON journal_entries(reference_type, reference_id) WHERE deleted_at = '' AND reference_type IN ('receipt_voucher', 'payment_voucher');");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON journal_entries(status, entry_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_store_branch ON journal_entries(store_id, branch_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_entries_reversed_entry ON journal_entries(reversed_entry_id);');

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
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_account_date_support ON journal_lines(account_id, entry_id);');
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

    // Phase 7: durable legacy-cash migration and reconciliation audit.
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_phase7_runs (
        id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT NOT NULL DEFAULT '',
        legacy_receipts_found INTEGER NOT NULL DEFAULT 0,
        legacy_payments_found INTEGER NOT NULL DEFAULT 0,
        vouchers_created INTEGER NOT NULL DEFAULT 0,
        allocations_created INTEGER NOT NULL DEFAULT 0,
        invoice_entries_created INTEGER NOT NULL DEFAULT 0,
        voucher_entries_created INTEGER NOT NULL DEFAULT 0,
        ledger_rows_created INTEGER NOT NULL DEFAULT 0,
        payment_caches_rebuilt INTEGER NOT NULL DEFAULT 0,
        issue_count INTEGER NOT NULL DEFAULT 0,
        message TEXT NOT NULL DEFAULT ''
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_phase7_runs_started ON cash_phase7_runs(started_at DESC);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_phase7_issues (
        id TEXT PRIMARY KEY NOT NULL,
        run_id TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT 'warning',
        issue_type TEXT NOT NULL,
        entity_type TEXT NOT NULL DEFAULT '',
        entity_id TEXT NOT NULL DEFAULT '',
        reference_no TEXT NOT NULL DEFAULT '',
        details TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (run_id) REFERENCES cash_phase7_runs(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_phase7_issues_run ON cash_phase7_issues(run_id, severity, issue_type);');

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
        is_important INTEGER NOT NULL DEFAULT 1,
        previous_hash TEXT NOT NULL DEFAULT '',
        record_hash TEXT NOT NULL DEFAULT '',
        hash_version INTEGER NOT NULL DEFAULT 1
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
    await _ensureColumn(
        'audit_logs', 'previous_hash', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'audit_logs', 'record_hash', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'audit_logs', 'hash_version', 'INTEGER NOT NULL DEFAULT 1');
    await _sealLegacyAuditRows();
    await customStatement(auditInsertGuardSql);
    await customStatement(r'''
      CREATE TRIGGER IF NOT EXISTS trg_audit_logs_no_update
      BEFORE UPDATE ON audit_logs
      BEGIN
        SELECT RAISE(ABORT, 'audit_logs are append-only');
      END;
    ''');
    await customStatement(r'''
      CREATE TRIGGER IF NOT EXISTS trg_audit_logs_no_delete
      BEFORE DELETE ON audit_logs
      BEGIN
        SELECT RAISE(ABORT, 'audit_logs are append-only');
      END;
    ''');

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
        reversed_at TEXT NOT NULL DEFAULT '',
        reversal_reason TEXT NOT NULL DEFAULT '',
        reversed_by TEXT NOT NULL DEFAULT '',
        reversed_by_user_id TEXT NOT NULL DEFAULT '',
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
    await _ensureColumn('cash_transfers', 'transfer_kind',
        "TEXT NOT NULL DEFAULT 'vault_transfer'");
    await _ensureColumn(
        'cash_transfers', 'from_session_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'to_session_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'created_by_user_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'device_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'idempotency_key', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_transfers', 'reversed_by_user_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_transfers_idempotency ON cash_transfers(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';");

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
        updated_at TEXT NOT NULL DEFAULT '',
        revision INTEGER NOT NULL DEFAULT 1,
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
    await _ensureColumn(
        'cash_drawer_sessions', 'updated_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_drawer_sessions', 'revision', 'INTEGER NOT NULL DEFAULT 1');
    await customStatement(
        "UPDATE cash_drawer_sessions SET updated_at = CASE WHEN closed_at <> '' THEN closed_at ELSE opened_at END WHERE updated_at = ''");
    await customStatement(
        "UPDATE cash_drawer_sessions SET revision = 2 WHERE status IN ('closed', 'void') AND revision < 2");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_location ON cash_drawer_sessions(cash_location_id, status);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_drawer_sessions_users ON cash_drawer_sessions(opened_by_user_id, closed_by_user_id);');

    // Phase 1 cash ledger: immutable, append-oriented cash movement source.
    // Existing sale/purchase/accounting flows are intentionally not switched to it yet.
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_ledger_transactions (
        id TEXT PRIMARY KEY NOT NULL,
        type TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'USD',
        cash_location_id TEXT NOT NULL,
        cash_drawer_session_id TEXT NOT NULL DEFAULT '',
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT NOT NULL DEFAULT '',
        reference_number TEXT NOT NULL DEFAULT '',
        party_type TEXT NOT NULL DEFAULT '',
        party_id TEXT NOT NULL DEFAULT '',
        party_name TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT 'Cash',
        created_by TEXT NOT NULL DEFAULT '',
        created_by_user_id TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        idempotency_key TEXT NOT NULL DEFAULT '',
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        reversal_of_id TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        CHECK (direction IN ('in', 'out')),
        CHECK (amount > 0)
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_ledger_location_time ON cash_ledger_transactions(cash_location_id, occurred_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_ledger_session_time ON cash_ledger_transactions(cash_drawer_session_id, occurred_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_ledger_reference ON cash_ledger_transactions(reference_type, reference_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_ledger_party ON cash_ledger_transactions(party_type, party_id, occurred_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_ledger_store_branch_time ON cash_ledger_transactions(store_id, branch_id, occurred_at DESC);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_ledger_idempotency ON cash_ledger_transactions(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';");

    // Phase 5 standalone cash operations. These rows bind the operational
    // action to its journal entry and immutable Cash Ledger movement.
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_operations (
        id TEXT PRIMARY KEY NOT NULL,
        operation_no TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        operation_date TEXT NOT NULL,
        cash_location_id TEXT NOT NULL,
        cash_drawer_session_id TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'USD',
        journal_entry_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'posted',
        reversed_at TEXT NOT NULL DEFAULT '',
        reversal_reason TEXT NOT NULL DEFAULT '',
        reversed_by TEXT NOT NULL DEFAULT '',
        reversed_by_user_id TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL DEFAULT '',
        created_by_user_id TEXT NOT NULL DEFAULT '',
        device_id TEXT NOT NULL DEFAULT '',
        store_id TEXT NOT NULL DEFAULT '',
        branch_id TEXT NOT NULL DEFAULT '',
        idempotency_key TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        last_modified_by_device_id TEXT NOT NULL DEFAULT '',
        CHECK (operation_type IN ('cash_deposit', 'cash_withdrawal', 'expense')),
        CHECK (amount > 0)
      );
    ''');
    await _ensureColumn(
        'cash_operations', 'status', "TEXT NOT NULL DEFAULT 'posted'");
    await _ensureColumn(
        'cash_operations', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_operations', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_operations', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'cash_operations', 'reversed_by_user_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_operations_location_date ON cash_operations(cash_location_id, operation_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_operations_session_date ON cash_operations(cash_drawer_session_id, operation_date DESC);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_operations_idempotency ON cash_operations(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';");

    // Phase 2 receipt/payment vouchers. These are independent financial events;
    // invoice paid_amount remains a compatibility cache updated from allocations.
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS receipt_vouchers (
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
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_customer_date ON receipt_vouchers(customer_id, voucher_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_session_date ON receipt_vouchers(cash_drawer_session_id, voucher_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_store_branch_date ON receipt_vouchers(store_id, branch_id, voucher_date DESC);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_receipt_vouchers_idempotency ON receipt_vouchers(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';");
    await _ensureColumn(
        'receipt_vouchers', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'receipt_vouchers', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'receipt_vouchers', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'receipt_vouchers', 'reversed_by_user_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'receipt_vouchers', 'discount', "REAL NOT NULL DEFAULT 0");

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS payment_vouchers (
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
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_supplier_date ON payment_vouchers(supplier_id, voucher_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_session_date ON payment_vouchers(cash_drawer_session_id, voucher_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_vouchers_store_branch_date ON payment_vouchers(store_id, branch_id, voucher_date DESC);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_vouchers_idempotency ON payment_vouchers(idempotency_key) WHERE idempotency_key <> '' AND deleted_at = '';");
    await _ensureColumn(
        'payment_vouchers', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_vouchers', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_vouchers', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_vouchers', 'reversed_by_user_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_vouchers', 'discount', "REAL NOT NULL DEFAULT 0");

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS payment_allocations (
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
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_allocations_voucher ON payment_allocations(voucher_type, voucher_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_allocations_reference ON payment_allocations(reference_type, reference_id);');
    await _ensureColumn(
        'payment_allocations', 'status', "TEXT NOT NULL DEFAULT 'active'");
    await _ensureColumn(
        'payment_allocations', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_allocations', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'payment_allocations', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('payment_allocations', 'reversed_by_user_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('payment_allocations', 'allocation_kind',
        "TEXT NOT NULL DEFAULT 'allocation'");
    await _ensureColumn(
        'payment_allocations', 'reversal_of_id', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'DROP INDEX IF EXISTS idx_payment_allocations_target_per_voucher;');
    await customStatement(
        'DROP INDEX IF EXISTS idx_payment_allocations_target_per_voucher_kind;');
    // Posted voucher edits preserve prior allocation rows as immutable reversed
    // history. Only the current active allocation for a voucher/target/kind must
    // be unique; historical reversed rows must not block a new edit version.
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_allocations_target_per_voucher_kind_active ON payment_allocations(voucher_type, voucher_id, reference_type, reference_id, allocation_kind, reversal_of_id) WHERE deleted_at = '' AND status = 'active';");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_allocations_status ON payment_allocations(status, reference_type, reference_id);');
    await _rebuildVoucherTablesForDiscountOnlySettlements();

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS cash_refund_allocations (
        id TEXT PRIMARY KEY NOT NULL,
        refund_id TEXT NOT NULL,
        voucher_type TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        allocation_kind TEXT NOT NULL,
        allocation_id TEXT NOT NULL DEFAULT '',
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        reference_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NOT NULL DEFAULT '',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        last_modified_by_device_id TEXT NOT NULL DEFAULT ''
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cash_refund_allocations_refund ON cash_refund_allocations(refund_id);');

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
}
