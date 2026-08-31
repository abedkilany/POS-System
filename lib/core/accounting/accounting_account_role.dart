class AccountingAccountRole {
  const AccountingAccountRole({
    required this.key,
    required this.titleAr,
    required this.descriptionAr,
    required this.defaultAccountId,
    required this.group,
    this.legacySettingKey = '',
  });

  final String key;
  final String titleAr;
  final String descriptionAr;
  final String defaultAccountId;
  final String group;
  final String legacySettingKey;

  String get settingKey => 'role_${key}_account_id';

  bool get syncsLegacySetting => legacySettingKey.trim().isNotEmpty;

  static const List<AccountingAccountRole> all = <AccountingAccountRole>[
    AccountingAccountRole(
      key: 'cash',
      titleAr: 'حساب النقدية الافتراضي',
      descriptionAr:
          'الحساب الأساسي المستخدم للعمليات النقدية التي لا ترتبط بدرج أو خزنة محددة.',
      defaultAccountId: 'acc_cash',
      group: 'core',
      legacySettingKey: 'default_cash_account_id',
    ),
    AccountingAccountRole(
      key: 'bank',
      titleAr: 'حساب البنك الافتراضي',
      descriptionAr: 'الحساب الأساسي المستخدم لعمليات البنك والبطاقات.',
      defaultAccountId: 'acc_bank',
      group: 'core',
      legacySettingKey: 'default_bank_account_id',
    ),
    AccountingAccountRole(
      key: 'accounts_receivable',
      titleAr: 'حساب العملاء',
      descriptionAr: 'حساب الرقابة للذمم المدينة على العملاء.',
      defaultAccountId: 'acc_customers',
      group: 'core',
      legacySettingKey: 'default_customers_account_id',
    ),
    AccountingAccountRole(
      key: 'accounts_payable',
      titleAr: 'حساب الموردين',
      descriptionAr: 'حساب الرقابة للذمم الدائنة للموردين.',
      defaultAccountId: 'acc_suppliers',
      group: 'core',
      legacySettingKey: 'default_suppliers_account_id',
    ),
    AccountingAccountRole(
      key: 'inventory_asset',
      titleAr: 'حساب أصل المخزون',
      descriptionAr:
          'حساب المخزون العام للتوافق التاريخي والتسويات فقط؛ الترحيل التشغيلي يستخدم حساب الخام/تحت التصنيع/التام/البضائع حسب نوع المنتج.',
      defaultAccountId: 'acc_inventory',
      group: 'inventory',
      legacySettingKey: 'default_inventory_account_id',
    ),
    AccountingAccountRole(
      key: 'inventory_raw',
      titleAr: 'مخزون المواد الخام',
      descriptionAr: 'قيمة المواد الخام قبل التصنيع.',
      defaultAccountId: 'acc_inventory_raw',
      group: 'inventory',
    ),
    AccountingAccountRole(
      key: 'inventory_wip',
      titleAr: 'مخزون تحت التصنيع',
      descriptionAr:
          'قيمة المواد والخلطات الموجودة ضمن عملية تصنيع غير مكتملة.',
      defaultAccountId: 'acc_inventory_wip',
      group: 'inventory',
    ),
    AccountingAccountRole(
      key: 'inventory_finished',
      titleAr: 'مخزون المنتجات التامة',
      descriptionAr: 'قيمة المنتجات المصنعة الجاهزة للبيع.',
      defaultAccountId: 'acc_inventory_finished',
      group: 'inventory',
    ),
    AccountingAccountRole(
      key: 'inventory_merchandise',
      titleAr: 'مخزون البضائع التجارية',
      descriptionAr: 'قيمة البضائع المشتراة لإعادة البيع دون تصنيع.',
      defaultAccountId: 'acc_inventory_merchandise',
      group: 'inventory',
    ),
    AccountingAccountRole(
      key: 'inventory_transit',
      titleAr: 'مخزون بالطريق',
      descriptionAr:
          'قيمة مخزون تم شراؤه أو نقله ولم يصل بعد إلى المستودع المستهدف.',
      defaultAccountId: 'acc_inventory_transit',
      group: 'inventory',
    ),
    AccountingAccountRole(
      key: 'sales_revenue',
      titleAr: 'إيرادات المبيعات',
      descriptionAr: 'الحساب الأساسي لإيرادات المبيعات.',
      defaultAccountId: 'acc_sales',
      group: 'sales',
      legacySettingKey: 'default_sales_account_id',
    ),
    AccountingAccountRole(
      key: 'sales_returns',
      titleAr: 'مردودات المبيعات',
      descriptionAr: 'الحساب المقابل للإيراد عند مرتجع المبيعات.',
      defaultAccountId: 'acc_sales_returns',
      group: 'sales',
    ),
    AccountingAccountRole(
      key: 'sales_discounts',
      titleAr: 'خصومات المبيعات',
      descriptionAr: 'الحساب المستخدم للخصومات الممنوحة على المبيعات.',
      defaultAccountId: 'acc_sales_discounts',
      group: 'sales',
    ),
    AccountingAccountRole(
      key: 'cogs',
      titleAr: 'تكلفة البضاعة المباعة',
      descriptionAr: 'الحساب الذي يستقبل تكلفة المنتجات عند البيع.',
      defaultAccountId: 'acc_cogs',
      group: 'sales',
      legacySettingKey: 'default_cogs_account_id',
    ),
    AccountingAccountRole(
      key: 'service_revenue',
      titleAr: 'إيرادات الخدمات',
      descriptionAr: 'إيرادات الخدمات غير المرتبطة ببيع المخزون.',
      defaultAccountId: 'acc_service_revenue',
      group: 'sales',
    ),
    AccountingAccountRole(
      key: 'other_revenue',
      titleAr: 'إيرادات أخرى',
      descriptionAr: 'إيرادات لا تنتمي إلى المبيعات أو الخدمات الرئيسية.',
      defaultAccountId: 'acc_other_revenue',
      group: 'sales',
    ),
    AccountingAccountRole(
      key: 'general_expense',
      titleAr: 'المصروف العام الافتراضي',
      descriptionAr:
          'حساب افتراضي للمصروف عندما لا يختار المستخدم حسابًا أكثر تحديدًا.',
      defaultAccountId: 'acc_general_expenses',
      group: 'expenses',
      legacySettingKey: 'default_expense_account_id',
    ),
    AccountingAccountRole(
      key: 'rent_expense',
      titleAr: 'مصروف الإيجار',
      descriptionAr: 'الحساب المستخدم لمصاريف الإيجارات.',
      defaultAccountId: 'acc_rent_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'electricity_expense',
      titleAr: 'مصروف الكهرباء',
      descriptionAr: 'الحساب المستخدم لمصاريف الكهرباء والطاقة الكهربائية.',
      defaultAccountId: 'acc_electricity_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'water_expense',
      titleAr: 'مصروف المياه',
      descriptionAr: 'الحساب المستخدم لمصاريف المياه.',
      defaultAccountId: 'acc_water_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'telecom_expense',
      titleAr: 'مصروف الهاتف والإنترنت',
      descriptionAr: 'الحساب المستخدم لمصاريف الهاتف والإنترنت والاتصالات.',
      defaultAccountId: 'acc_telecom_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'payroll_expense',
      titleAr: 'مصروف الرواتب والأجور',
      descriptionAr:
          'الحساب المستخدم للرواتب والأجور والمكافآت المرتبطة بالموظفين.',
      defaultAccountId: 'acc_payroll_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'transport_expense',
      titleAr: 'مصروف النقل والمحروقات',
      descriptionAr:
          'الحساب المستخدم للنقل والمحروقات والتوصيل ومواصلات الموظفين.',
      defaultAccountId: 'acc_transport_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'maintenance_expense',
      titleAr: 'مصروف الصيانة',
      descriptionAr:
          'الحساب المستخدم لمصاريف الصيانة التشغيلية وصيانة المركبات.',
      defaultAccountId: 'acc_maintenance_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'marketing_expense',
      titleAr: 'مصروف الدعاية والتسويق',
      descriptionAr: 'الحساب المستخدم للإعلانات والتصميم والترويج والتسويق.',
      defaultAccountId: 'acc_marketing_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'office_expense',
      titleAr: 'مصروفات مكتبية وقرطاسية',
      descriptionAr:
          'الحساب المستخدم للقرطاسية والطباعة والتنظيف والمستلزمات المكتبية.',
      defaultAccountId: 'acc_office_expense',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'bank_fees',
      titleAr: 'رسوم وعمولات بنكية',
      descriptionAr: 'الحساب المخصص لرسوم البنوك ومزودي الدفع.',
      defaultAccountId: 'acc_bank_fees',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'bad_debts',
      titleAr: 'ديون معدومة',
      descriptionAr: 'الخسائر الناتجة عن ديون عملاء ثبت عدم تحصيلها.',
      defaultAccountId: 'acc_bad_debts',
      group: 'expenses',
    ),
    AccountingAccountRole(
      key: 'inventory_count_loss',
      titleAr: 'خسائر فروقات جرد المخزون',
      descriptionAr: 'الحساب المستخدم عند وجود نقص فعلي في الجرد.',
      defaultAccountId: 'acc_inventory_count_loss',
      group: 'inventory_adjustments',
    ),
    AccountingAccountRole(
      key: 'inventory_count_gain',
      titleAr: 'أرباح فروقات جرد المخزون',
      descriptionAr: 'الحساب المستخدم عند وجود زيادة فعلية في الجرد.',
      defaultAccountId: 'acc_inventory_count_gain',
      group: 'inventory_adjustments',
    ),
    AccountingAccountRole(
      key: 'inventory_damage',
      titleAr: 'تلف المخزون',
      descriptionAr: 'الخسارة الناتجة عن تلف المخزون.',
      defaultAccountId: 'acc_inventory_damage',
      group: 'inventory_adjustments',
    ),
    AccountingAccountRole(
      key: 'inventory_expiry',
      titleAr: 'انتهاء صلاحية المخزون',
      descriptionAr: 'الخسارة الناتجة عن انتهاء صلاحية المخزون.',
      defaultAccountId: 'acc_inventory_expiry',
      group: 'inventory_adjustments',
    ),
    AccountingAccountRole(
      key: 'inventory_weight_variance',
      titleAr: 'فروقات وزن المخزون',
      descriptionAr: 'الفروقات الناتجة عن تفاوت الوزن الفعلي عن الوزن المسجل.',
      defaultAccountId: 'acc_inventory_weight_variance',
      group: 'inventory_adjustments',
    ),
    AccountingAccountRole(
      key: 'manufacturing_cost',
      titleAr: 'تكلفة التصنيع',
      descriptionAr:
          'الحساب المخصص لتكلفة التصنيع عند الحاجة إلى ترحيلها بشكل منفصل.',
      defaultAccountId: 'acc_manufacturing_cost',
      group: 'manufacturing',
    ),
    AccountingAccountRole(
      key: 'manufacturing_cost_variance',
      titleAr: 'فروقات تكلفة التصنيع',
      descriptionAr:
          'الحساب المستخدم لفروقات التكلفة الفعلية عن التكلفة المتوقعة.',
      defaultAccountId: 'acc_manufacturing_cost_variance',
      group: 'manufacturing',
    ),
    AccountingAccountRole(
      key: 'manufacturing_waste',
      titleAr: 'هدر التصنيع',
      descriptionAr: 'الخسائر الناتجة عن هدر المواد أثناء التصنيع.',
      defaultAccountId: 'acc_manufacturing_waste',
      group: 'manufacturing',
    ),
    AccountingAccountRole(
      key: 'cash_short',
      titleAr: 'عجز الصندوق',
      descriptionAr:
          'الحساب المستخدم عندما يكون النقد الفعلي أقل من رصيد النظام.',
      defaultAccountId: 'acc_cash_short',
      group: 'cash',
    ),
    AccountingAccountRole(
      key: 'cash_over',
      titleAr: 'زيادة الصندوق',
      descriptionAr:
          'الحساب المستخدم عندما يكون النقد الفعلي أعلى من رصيد النظام.',
      defaultAccountId: 'acc_cash_over',
      group: 'cash',
    ),
    AccountingAccountRole(
      key: 'suspense_unknown',
      titleAr: 'مبالغ معلقة مجهولة المصدر',
      descriptionAr: 'حساب وسيط لمبالغ لا يُعرف مصدرها أو وجهتها بعد.',
      defaultAccountId: 'acc_suspense_unknown',
      group: 'cash',
    ),
    AccountingAccountRole(
      key: 'temporary_clearing',
      titleAr: 'حساب تسويات مؤقت',
      descriptionAr: 'حساب وسيط للعمليات التي تحتاج تسوية لاحقة.',
      defaultAccountId: 'acc_temporary_clearing',
      group: 'cash',
    ),
    AccountingAccountRole(
      key: 'cash_transfer_clearing',
      titleAr: 'تحويلات نقدية قيد التسوية',
      descriptionAr:
          'حساب وسيط للتحويلات النقدية التي لم تكتمل في الطرفين بعد.',
      defaultAccountId: 'acc_cash_transfer_clearing',
      group: 'cash',
    ),
    AccountingAccountRole(
      key: 'supplier_advances',
      titleAr: 'دفعات مقدمة للموردين',
      descriptionAr: 'رصيد دفعات تم دفعها للمورد قبل استحقاق فاتورة محددة.',
      defaultAccountId: 'acc_supplier_advances',
      group: 'parties',
    ),
    AccountingAccountRole(
      key: 'customer_advances',
      titleAr: 'دفعات مقدمة من العملاء',
      descriptionAr: 'رصيد دفعات استلمت من العميل قبل استحقاق فاتورة محددة.',
      defaultAccountId: 'acc_customer_advances',
      group: 'parties',
    ),
    AccountingAccountRole(
      key: 'owner_capital',
      titleAr: 'رأس مال المالك',
      descriptionAr: 'الحساب الذي يمثل رأس المال المستثمر في المنشأة.',
      defaultAccountId: 'acc_owner_capital',
      group: 'equity',
      legacySettingKey: 'default_equity_account_id',
    ),
    AccountingAccountRole(
      key: 'owner_current',
      titleAr: 'جاري المالك',
      descriptionAr:
          'الحساب المستخدم لحركات المالك التي لا تمثل رأس مال دائمًا.',
      defaultAccountId: 'acc_owner_current',
      group: 'equity',
    ),
    AccountingAccountRole(
      key: 'owner_drawings',
      titleAr: 'مسحوبات المالك',
      descriptionAr:
          'الحساب المستخدم للمبالغ أو الموجودات التي يسحبها المالك للاستخدام الشخصي.',
      defaultAccountId: 'acc_owner_drawings',
      group: 'equity',
    ),
    AccountingAccountRole(
      key: 'retained_earnings',
      titleAr: 'الأرباح المحتجزة',
      descriptionAr: 'أرباح السنوات السابقة المتراكمة داخل المنشأة.',
      defaultAccountId: 'acc_retained_earnings',
      group: 'equity',
    ),
    AccountingAccountRole(
      key: 'current_year_pnl',
      titleAr: 'أرباح وخسائر السنة الحالية',
      descriptionAr: 'الحساب المستخدم عند إقفال نتيجة السنة المالية.',
      defaultAccountId: 'acc_current_year_pnl',
      group: 'equity',
    ),
    AccountingAccountRole(
      key: 'fixed_assets',
      titleAr: 'الأصول الثابتة',
      descriptionAr: 'الحساب الافتراضي لإثبات اقتناء الأصول الثابتة.',
      defaultAccountId: 'acc_fixed_assets',
      group: 'fixed_assets',
      legacySettingKey: 'default_fixed_assets_account_id',
    ),
    AccountingAccountRole(
      key: 'accumulated_depreciation',
      titleAr: 'مجمع الإهلاك',
      descriptionAr: 'الحساب المقابل لتراكم إهلاك الأصول الثابتة.',
      defaultAccountId: 'acc_accum_depreciation',
      group: 'fixed_assets',
      legacySettingKey: 'default_accumulated_depreciation_account_id',
    ),
    AccountingAccountRole(
      key: 'depreciation_expense',
      titleAr: 'مصروف الإهلاك',
      descriptionAr: 'الحساب المستخدم لإثبات مصروف إهلاك الفترة.',
      defaultAccountId: 'acc_depreciation_expense',
      group: 'fixed_assets',
      legacySettingKey: 'default_depreciation_expense_account_id',
    ),
    AccountingAccountRole(
      key: 'sales_tax',
      titleAr: 'ضريبة المبيعات',
      descriptionAr: 'حساب الضريبة الناتجة عن فواتير المبيعات.',
      defaultAccountId: 'acc_vat_output',
      group: 'tax',
      legacySettingKey: 'default_sales_tax_account_id',
    ),
    AccountingAccountRole(
      key: 'purchase_tax',
      titleAr: 'ضريبة المشتريات',
      descriptionAr: 'حساب الضريبة القابلة للاسترداد على المشتريات.',
      defaultAccountId: 'acc_vat_input',
      group: 'tax',
      legacySettingKey: 'default_purchase_tax_account_id',
    ),
    AccountingAccountRole(
      key: 'tax_payable',
      titleAr: 'الضريبة المستحقة',
      descriptionAr: 'الحساب المستخدم لصافي الضريبة المستحقة عند التسوية.',
      defaultAccountId: 'acc_vat_output',
      group: 'tax',
      legacySettingKey: 'default_tax_payable_account_id',
    ),
  ];

  static AccountingAccountRole? byKey(String key) {
    final normalized = key.trim();
    for (final role in all) {
      if (role.key == normalized || role.settingKey == normalized) return role;
    }
    return null;
  }

  static AccountingAccountRole? byLegacySettingKey(String key) {
    final normalized = key.trim();
    for (final role in all) {
      if (role.legacySettingKey == normalized && normalized.isNotEmpty) {
        return role;
      }
    }
    return null;
  }
}
