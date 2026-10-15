part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods7 on VentioDriftDatabase {
  Future<void> _seedDefaultChartOfAccounts() async {
    final now = DateTime.now().toUtc().toIso8601String();
    // [id, code, name, type, subtype, parentId, normalBalance, isPostable]
    // Existing IDs/codes stay untouched so historic journal references remain
    // valid on upgraded databases. New rows are added idempotently.
    final accounts = <List<String>>[
      ['acc_assets', '1000', 'الأصول', 'asset', 'group', '', 'debit', '0'],
      [
        'acc_cash',
        '1100',
        'النقدية',
        'asset',
        'cash',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_main_vault',
        '1110',
        'الخزنة الرئيسية',
        'asset',
        'cash_location',
        'acc_cash',
        'debit',
        '1'
      ],
      [
        'acc_main_drawer',
        '1120',
        'درج النقد الرئيسي',
        'asset',
        'cash_location',
        'acc_cash',
        'debit',
        '1'
      ],
      [
        'acc_bank',
        '1200',
        'البنوك',
        'asset',
        'bank',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_main_bank',
        '1210',
        'البنك الرئيسي',
        'asset',
        'bank_location',
        'acc_bank',
        'debit',
        '1'
      ],
      [
        'acc_customers',
        '1300',
        'العملاء / الذمم المدينة',
        'asset',
        'receivable',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_notes_receivable',
        '1310',
        'أوراق القبض',
        'asset',
        'notes_receivable',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_doubtful_allowance',
        '1320',
        'مخصص الديون المشكوك فيها',
        'asset',
        'contra_receivable',
        'acc_assets',
        'credit',
        '1'
      ],
      [
        'acc_inventory',
        '1400',
        'المخزون',
        'asset',
        'inventory',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_inventory_raw',
        '1410',
        'مخزون المواد الخام',
        'asset',
        'inventory_raw',
        'acc_inventory',
        'debit',
        '1'
      ],
      [
        'acc_inventory_wip',
        '1420',
        'مخزون تحت التصنيع',
        'asset',
        'inventory_wip',
        'acc_inventory',
        'debit',
        '1'
      ],
      [
        'acc_inventory_finished',
        '1430',
        'مخزون المنتجات التامة',
        'asset',
        'inventory_finished',
        'acc_inventory',
        'debit',
        '1'
      ],
      [
        'acc_inventory_merchandise',
        '1440',
        'مخزون البضائع التجارية',
        'asset',
        'inventory_merchandise',
        'acc_inventory',
        'debit',
        '1'
      ],
      [
        'acc_inventory_transit',
        '1450',
        'مخزون بالطريق',
        'asset',
        'inventory_transit',
        'acc_inventory',
        'debit',
        '1'
      ],
      [
        'acc_vat_input',
        '1500',
        'ضريبة المدخلات / ضريبة قابلة للاسترداد',
        'asset',
        'tax_input',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_supplier_advances',
        '1510',
        'دفعات مقدمة للموردين',
        'asset',
        'supplier_advances',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_prepaid_expenses',
        '1520',
        'مصروفات مدفوعة مقدمًا',
        'asset',
        'prepaid_expenses',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_cash_transfer_transit',
        '1530',
        'تحويلات نقدية قيد التسوية',
        'asset',
        'cash_clearing',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_assets',
        '1600',
        'الأصول الثابتة',
        'asset',
        'fixed_assets',
        'acc_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_equipment',
        '1610',
        'معدات وآلات',
        'asset',
        'fixed_equipment',
        'acc_fixed_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_furniture',
        '1620',
        'أثاث وتجهيزات',
        'asset',
        'fixed_furniture',
        'acc_fixed_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_computers',
        '1630',
        'أجهزة وحواسيب',
        'asset',
        'fixed_computers',
        'acc_fixed_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_vehicles',
        '1640',
        'سيارات',
        'asset',
        'fixed_vehicles',
        'acc_fixed_assets',
        'debit',
        '1'
      ],
      [
        'acc_fixed_other',
        '1650',
        'أصول ثابتة أخرى',
        'asset',
        'fixed_other',
        'acc_fixed_assets',
        'debit',
        '1'
      ],
      [
        'acc_accum_depreciation',
        '1690',
        'مجمع الإهلاك',
        'asset',
        'accumulated_depreciation',
        'acc_assets',
        'credit',
        '1'
      ],

      [
        'acc_liabilities',
        '2000',
        'الالتزامات',
        'liability',
        'group',
        '',
        'credit',
        '0'
      ],
      [
        'acc_suppliers',
        '2100',
        'الموردون / الذمم الدائنة',
        'liability',
        'payable',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_notes_payable',
        '2110',
        'أوراق الدفع',
        'liability',
        'notes_payable',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_customer_advances',
        '2120',
        'دفعات مقدمة من العملاء',
        'liability',
        'customer_advances',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_vat_output',
        '2200',
        'ضريبة المخرجات / ضريبة مستحقة',
        'liability',
        'tax_payable',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_accrued_expenses',
        '2210',
        'مصروفات مستحقة',
        'liability',
        'accrued_expenses',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_accrued_payroll',
        '2220',
        'رواتب مستحقة',
        'liability',
        'accrued_payroll',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_short_term_loans',
        '2300',
        'قروض قصيرة الأجل',
        'liability',
        'short_term_loans',
        'acc_liabilities',
        'credit',
        '1'
      ],
      [
        'acc_long_term_loans',
        '2400',
        'قروض طويلة الأجل',
        'liability',
        'long_term_loans',
        'acc_liabilities',
        'credit',
        '1'
      ],

      [
        'acc_equity',
        '3000',
        'حقوق الملكية',
        'equity',
        'group',
        '',
        'credit',
        '0'
      ],
      [
        'acc_owner_capital',
        '3100',
        'رأس مال المالك',
        'equity',
        'capital',
        'acc_equity',
        'credit',
        '1'
      ],
      [
        'acc_owner_current',
        '3200',
        'جاري المالك',
        'equity',
        'owner_current',
        'acc_equity',
        'credit',
        '1'
      ],
      [
        'acc_owner_drawings',
        '3210',
        'مسحوبات المالك',
        'equity',
        'owner_drawings',
        'acc_equity',
        'debit',
        '1'
      ],
      [
        'acc_retained_earnings',
        '3300',
        'أرباح محتجزة',
        'equity',
        'retained_earnings',
        'acc_equity',
        'credit',
        '1'
      ],
      [
        'acc_current_year_pnl',
        '3400',
        'أرباح وخسائر السنة الحالية',
        'equity',
        'current_year_pnl',
        'acc_equity',
        'credit',
        '1'
      ],

      [
        'acc_revenue',
        '4000',
        'الإيرادات',
        'revenue',
        'group',
        '',
        'credit',
        '0'
      ],
      [
        'acc_sales',
        '4100',
        'إيرادات المبيعات',
        'revenue',
        'sales',
        'acc_revenue',
        'credit',
        '1'
      ],
      [
        'acc_sales_returns',
        '4110',
        'مردودات المبيعات',
        'revenue',
        'sales_returns',
        'acc_revenue',
        'debit',
        '1'
      ],
      [
        'acc_sales_discounts',
        '4120',
        'خصومات المبيعات',
        'revenue',
        'sales_discounts',
        'acc_revenue',
        'debit',
        '1'
      ],
      [
        'acc_customer_settlement_discount',
        '4130',
        'خصومات تسوية العملاء',
        'revenue',
        'customer_settlement_discount',
        'acc_revenue',
        'debit',
        '1'
      ],
      [
        'acc_service_revenue',
        '4200',
        'إيرادات خدمات',
        'revenue',
        'service_revenue',
        'acc_revenue',
        'credit',
        '1'
      ],
      [
        'acc_other_revenue',
        '4300',
        'إيرادات أخرى',
        'revenue',
        'other_revenue',
        'acc_revenue',
        'credit',
        '1'
      ],
      [
        'acc_inventory_count_gain',
        '4400',
        'أرباح فروقات جرد المخزون',
        'revenue',
        'inventory_count_gain',
        'acc_revenue',
        'credit',
        '1'
      ],
      [
        'acc_cash_over',
        '4500',
        'زيادة الصندوق',
        'revenue',
        'cash_over',
        'acc_revenue',
        'credit',
        '1'
      ],

      [
        'acc_cost_of_sales',
        '5000',
        'تكلفة المبيعات',
        'cost_of_sales',
        'group',
        '',
        'debit',
        '0'
      ],
      [
        'acc_cogs',
        '5100',
        'تكلفة البضاعة المباعة',
        'cost_of_sales',
        'cogs',
        'acc_cost_of_sales',
        'debit',
        '1'
      ],
      [
        'acc_manufacturing_cost',
        '5200',
        'تكلفة التصنيع',
        'cost_of_sales',
        'manufacturing_cost',
        'acc_cost_of_sales',
        'debit',
        '1'
      ],
      [
        'acc_manufacturing_cost_variance',
        '5210',
        'فروقات تكلفة التصنيع',
        'cost_of_sales',
        'manufacturing_cost_variance',
        'acc_cost_of_sales',
        'debit',
        '1'
      ],

      [
        'acc_expenses',
        '6000',
        'المصروفات',
        'expense',
        'group',
        '',
        'debit',
        '0'
      ],
      [
        'acc_general_expenses',
        '6100',
        'مصروفات عامة',
        'expense',
        'general',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_supplier_settlement_discount',
        '6220',
        'خصومات تسوية الموردين',
        'revenue',
        'supplier_settlement_discount',
        'acc_revenue',
        'credit',
        '1'
      ],
      [
        'acc_rent_expense',
        '6110',
        'إيجارات',
        'expense',
        'rent',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_electricity_expense',
        '6120',
        'كهرباء',
        'expense',
        'electricity',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_water_expense',
        '6130',
        'مياه',
        'expense',
        'water',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_telecom_expense',
        '6140',
        'هاتف وإنترنت',
        'expense',
        'telecom',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_payroll_expense',
        '6150',
        'رواتب وأجور',
        'expense',
        'payroll',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_transport_expense',
        '6160',
        'نقل ومحروقات',
        'expense',
        'transport',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_maintenance_expense',
        '6170',
        'صيانة',
        'expense',
        'maintenance',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_marketing_expense',
        '6180',
        'دعاية وتسويق',
        'expense',
        'marketing',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_office_expense',
        '6190',
        'قرطاسية ومصاريف مكتبية',
        'expense',
        'office',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_cash_over_short',
        '6200',
        'زيادة / عجز النقدية',
        'expense',
        'cash_reconciliation',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_cash_short',
        '6210',
        'عجز الصندوق',
        'expense',
        'cash_short',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_depreciation_expense',
        '6300',
        'مصروف الإهلاك',
        'expense',
        'depreciation',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_bank_fees',
        '6400',
        'رسوم وعمولات بنكية',
        'expense',
        'bank_fees',
        'acc_expenses',
        'debit',
        '1'
      ],
      [
        'acc_bad_debts',
        '6500',
        'ديون معدومة',
        'expense',
        'bad_debts',
        'acc_expenses',
        'debit',
        '1'
      ],

      [
        'acc_inventory_variances',
        '7000',
        'فروقات وخسائر المخزون',
        'expense',
        'group',
        '',
        'debit',
        '0'
      ],
      [
        'acc_inventory_count_loss',
        '7100',
        'خسائر فروقات جرد المخزون',
        'expense',
        'inventory_count_loss',
        'acc_inventory_variances',
        'debit',
        '1'
      ],
      [
        'acc_manufacturing_waste',
        '7200',
        'هدر التصنيع',
        'expense',
        'manufacturing_waste',
        'acc_inventory_variances',
        'debit',
        '1'
      ],
      [
        'acc_inventory_damage',
        '7300',
        'تلف المخزون',
        'expense',
        'inventory_damage',
        'acc_inventory_variances',
        'debit',
        '1'
      ],
      [
        'acc_inventory_expiry',
        '7310',
        'انتهاء صلاحية',
        'expense',
        'inventory_expiry',
        'acc_inventory_variances',
        'debit',
        '1'
      ],
      [
        'acc_inventory_weight_variance',
        '7400',
        'فروقات وزن المخزون',
        'expense',
        'inventory_weight_variance',
        'acc_inventory_variances',
        'debit',
        '1'
      ],

      // Visual grouping only. Children retain their own accounting type so
      // balance-sheet reporting classifies each clearing account correctly.
      [
        'acc_temporary',
        '8000',
        'الحسابات المؤقتة والتسويات',
        'liability',
        'group',
        '',
        'credit',
        '0'
      ],
      [
        'acc_suspense_unknown',
        '8100',
        'مبالغ معلقة مجهولة المصدر',
        'liability',
        'suspense_unknown',
        'acc_temporary',
        'credit',
        '1'
      ],
      [
        'acc_temporary_clearing',
        '8200',
        'حساب تسويات مؤقت',
        'asset',
        'temporary_clearing',
        'acc_temporary',
        'debit',
        '1'
      ],
      [
        'acc_cash_transfer_clearing',
        '8300',
        'تحويلات نقدية قيد التسوية',
        'asset',
        'cash_transfer_clearing',
        'acc_temporary',
        'debit',
        '1'
      ],
    ];

    for (final account in accounts) {
      await customInsert(
        r'''
        INSERT OR IGNORE INTO accounts
          (id, code, name, type, subtype, parent_id, normal_balance, currency,
           is_system, is_postable, is_active, description, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 1, ?, ?, ?)
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
          Variable<int>(int.tryParse(account[7]) ?? 1),
          const Variable<String>('حساب افتراضي أساسي للمحاسبة'),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    // Existing system group rows predate is_postable, so explicitly migrate
    // only true grouping accounts. Legacy control accounts stay postable in
    // Phase 1 to avoid changing any current sale/purchase/inventory posting.
    await customUpdate(
      "UPDATE accounts SET is_postable = 0, updated_at = ? WHERE is_system = 1 AND subtype = 'group' AND deleted_at = ''",
      variables: <Variable<Object>>[Variable<String>(now)],
    );

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
        'default_equity_account_id',
        'acc_owner_capital',
        'حساب حقوق الملكية الافتراضي للأرصدة الافتتاحية'
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
              ? '11'
              : setting[0] == 'default_vat_rate_percent'
                  ? '0'
                  : ''),
          Variable<String>(setting[2]),
          Variable<String>(now),
        ],
      );
    }

    // Phase 2: seed semantic posting roles. Existing installations inherit
    // the currently selected legacy default for one-to-one mappings so an
    // upgrade never silently changes a live posting account. New roles use
    // their dedicated Phase 1 account as the initial default.
    for (final role in AccountingAccountRole.all) {
      var accountId = role.defaultAccountId;
      if (role.syncsLegacySetting) {
        final legacy = await customSelect(
          'SELECT account_id FROM accounting_settings WHERE key = ? LIMIT 1',
          variables: <Variable<Object>>[
            Variable<String>(role.legacySettingKey),
          ],
        ).getSingleOrNull();
        final legacyId = legacy?.data['account_id']?.toString().trim() ?? '';
        if (legacyId.isNotEmpty) accountId = legacyId;
      }
      await customInsert(
        r'''
        INSERT OR IGNORE INTO accounting_settings
          (key, account_id, value, description, updated_at)
        VALUES (?, ?, '', ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(role.settingKey),
          Variable<String>(accountId),
          Variable<String>('Phase 2 account role: ${role.titleAr}'),
          Variable<String>(now),
        ],
      );
    }
  }
}
