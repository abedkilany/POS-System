part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods8 on VentioDriftDatabase {
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
      VALUES ('accounting_engine_version', '', '13', 'إصدار بنية وبذور محرك المحاسبة', ?)
      ON CONFLICT(key) DO UPDATE SET value = '13', updated_at = excluded.updated_at
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
      "UPDATE accounting_settings SET value = '13', description = 'إصدار بنية وبذور محرك المحاسبة', updated_at = ? WHERE key = 'accounting_engine_version'",
      variables: <Variable<Object>>[Variable<String>(now)],
    );
  }

  Future<void> _ensureWarehouseTransferOrderColumns() async {
    await _ensureColumn(
        'warehouse_transfer_orders', 'order_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'from_warehouse_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'from_warehouse_name',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'to_warehouse_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'to_warehouse_name',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'document_date',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'status',
        "TEXT NOT NULL DEFAULT 'completed'");
    await _ensureColumn(
        'warehouse_transfer_orders', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'created_by_user_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'created_by_user_name',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouse_transfer_orders', 'items_json',
        "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn(
        'warehouse_transfer_orders', 'total_units', 'REAL NOT NULL DEFAULT 0');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_warehouse_transfer_orders_order_no ON warehouse_transfer_orders(order_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_transfer_orders_date ON warehouse_transfer_orders(document_date DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_warehouse_transfer_orders_route ON warehouse_transfer_orders(from_warehouse_id, to_warehouse_id, document_date DESC);');
  }

  Future<void> _ensureAssistantChatHistorySchema() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS assistant_conversations (
        id TEXT PRIMARY KEY NOT NULL,
        scope_hash TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assistant_conversations_scope_updated ON assistant_conversations(scope_hash, updated_at DESC);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS assistant_chat_turns (
        id TEXT PRIMARY KEY NOT NULL,
        conversation_id TEXT NOT NULL,
        scope_hash TEXT NOT NULL,
        user_content TEXT NOT NULL,
        assistant_content TEXT NOT NULL DEFAULT '',
        assistant_status TEXT NOT NULL DEFAULT 'pending',
        attachment_name TEXT NOT NULL DEFAULT '',
        reports_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES assistant_conversations(id)
          ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assistant_chat_turns_conversation_created ON assistant_chat_turns(conversation_id, created_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assistant_chat_turns_scope_status ON assistant_chat_turns(scope_hash, assistant_status);');
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
