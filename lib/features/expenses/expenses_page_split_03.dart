// ignore_for_file: curly_braces_in_flow_control_structures
part of 'expenses_page.dart';

class _ExpenseDialogState extends State<_ExpenseDialog> {
  static const _categoriesKey = 'expense_categories_master_v1';
  static const _typesKey = 'expense_types_master_v1';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController notesController;
  String amountCurrency = 'USD';
  String? selectedCategory;
  String? selectedExpenseType;
  late DateTime selectedDate;

  late List<_ExpenseCatalogItem> _categories;
  late Map<String, List<_ExpenseCatalogItem>> _typesByCategory;

  static const List<_ExpenseCatalogItem> _defaultCategories = [
    _ExpenseCatalogItem(en: 'Utilities', ar: 'خدمات ومرافق'),
    _ExpenseCatalogItem(en: 'Office', ar: 'مكتب'),
    _ExpenseCatalogItem(en: 'Vehicles', ar: 'مركبات'),
    _ExpenseCatalogItem(en: 'Operations', ar: 'تشغيل'),
    _ExpenseCatalogItem(en: 'Marketing', ar: 'تسويق'),
    _ExpenseCatalogItem(en: 'Financial', ar: 'مالية'),
    _ExpenseCatalogItem(en: 'Staff', ar: 'موظفون'),
    _ExpenseCatalogItem(en: 'Other', ar: 'أخرى'),
  ];

  static const Map<String, List<_ExpenseCatalogItem>> _defaultTypes = {
    'Utilities': [
      _ExpenseCatalogItem(en: 'Electricity', ar: 'كهرباء'),
      _ExpenseCatalogItem(en: 'Water', ar: 'مياه'),
      _ExpenseCatalogItem(en: 'Internet', ar: 'إنترنت'),
      _ExpenseCatalogItem(en: 'Gas', ar: 'غاز'),
    ],
    'Office': [
      _ExpenseCatalogItem(en: 'Rent', ar: 'إيجار'),
      _ExpenseCatalogItem(en: 'Stationery', ar: 'قرطاسية'),
      _ExpenseCatalogItem(en: 'Printing', ar: 'طباعة'),
      _ExpenseCatalogItem(en: 'Cleaning', ar: 'تنظيف'),
      _ExpenseCatalogItem(en: 'Furniture', ar: 'أثاث'),
    ],
    'Vehicles': [
      _ExpenseCatalogItem(en: 'Fuel', ar: 'وقود'),
      _ExpenseCatalogItem(en: 'Maintenance', ar: 'صيانة'),
      _ExpenseCatalogItem(en: 'Insurance', ar: 'تأمين'),
      _ExpenseCatalogItem(en: 'Parking', ar: 'مواقف'),
    ],
    'Operations': [
      _ExpenseCatalogItem(en: 'Maintenance', ar: 'صيانة'),
      _ExpenseCatalogItem(en: 'Supplies', ar: 'مستلزمات'),
      _ExpenseCatalogItem(en: 'Delivery', ar: 'توصيل'),
      _ExpenseCatalogItem(en: 'Packaging', ar: 'تغليف'),
    ],
    'Marketing': [
      _ExpenseCatalogItem(en: 'Advertising', ar: 'إعلانات'),
      _ExpenseCatalogItem(en: 'Design', ar: 'تصميم'),
      _ExpenseCatalogItem(en: 'Social Media', ar: 'تواصل اجتماعي'),
      _ExpenseCatalogItem(en: 'Promotions', ar: 'عروض ترويجية'),
    ],
    'Financial': [
      _ExpenseCatalogItem(en: 'Bank Fees', ar: 'رسوم بنكية'),
      _ExpenseCatalogItem(en: 'Taxes', ar: 'ضرائب'),
      _ExpenseCatalogItem(en: 'Insurance', ar: 'تأمين'),
      _ExpenseCatalogItem(en: 'Commissions', ar: 'عمولات'),
    ],
    'Staff': [
      _ExpenseCatalogItem(en: 'Salaries', ar: 'رواتب'),
      _ExpenseCatalogItem(en: 'Bonuses', ar: 'مكافآت'),
      _ExpenseCatalogItem(en: 'Meals', ar: 'وجبات'),
      _ExpenseCatalogItem(en: 'Transportation', ar: 'مواصلات'),
    ],
    'Other': [_ExpenseCatalogItem(en: 'General Expense', ar: 'مصروف عام')],
  };

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _mergeLegacyExpensesIntoCatalog();
    final expense = widget.expense;
    selectedCategory = _normalizeInitialCategory(expense?.category);
    selectedExpenseType =
        _normalizeInitialType(expense?.title, selectedCategory);
    amountCurrency =
        expense?.originalCurrency ?? widget.storeProfile.defaultProductCurrency;
    amountController = TextEditingController(
        text: (expense?.originalAmount ?? expense?.amount)?.toString() ?? '');
    notesController = TextEditingController(text: expense?.notes ?? '');
    selectedDate = expense?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    amountController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _loadCatalog() {
    _categories = _decodeItemList(
        LocalDatabaseService.getString(_categoriesKey), _defaultCategories);
    _typesByCategory = _decodeTypesMap(
        LocalDatabaseService.getString(_typesKey), _defaultTypes);
  }

  List<_ExpenseCatalogItem> _decodeItemList(
      String? raw, List<_ExpenseCatalogItem> fallback) {
    if (raw == null || raw.trim().isEmpty)
      return List<_ExpenseCatalogItem>.from(fallback);
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .whereType<Map>()
          .map((item) =>
              _ExpenseCatalogItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.en.isNotEmpty)
          .toList();
      return items.isEmpty ? List<_ExpenseCatalogItem>.from(fallback) : items;
    } catch (_) {
      return List<_ExpenseCatalogItem>.from(fallback);
    }
  }

  Map<String, List<_ExpenseCatalogItem>> _decodeTypesMap(
      String? raw, Map<String, List<_ExpenseCatalogItem>> fallback) {
    if (raw == null || raw.trim().isEmpty)
      return fallback.map(
          (key, value) => MapEntry(key, List<_ExpenseCatalogItem>.from(value)));
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, List<_ExpenseCatalogItem>>{};
      for (final entry in decoded.entries) {
        final list = entry.value is List
            ? entry.value as List<dynamic>
            : const <dynamic>[];
        result[entry.key] = list
            .whereType<Map>()
            .map((item) =>
                _ExpenseCatalogItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.en.isNotEmpty)
            .toList();
      }
      return result.isEmpty
          ? fallback.map((key, value) =>
              MapEntry(key, List<_ExpenseCatalogItem>.from(value)))
          : result;
    } catch (_) {
      return fallback.map(
          (key, value) => MapEntry(key, List<_ExpenseCatalogItem>.from(value)));
    }
  }

  void _mergeLegacyExpensesIntoCatalog() {
    var changed = false;
    for (final expense in widget.existingExpenses) {
      final category = expense.category.trim();
      final type = expense.title.trim();
      if (category.isEmpty) continue;
      if (!_categories
          .any((item) => item.en.toLowerCase() == category.toLowerCase())) {
        _categories.add(_ExpenseCatalogItem(en: category, ar: ''));
        changed = true;
      }
      final types =
          _typesByCategory.putIfAbsent(category, () => <_ExpenseCatalogItem>[]);
      if (type.isNotEmpty &&
          !types.any((item) => item.en.toLowerCase() == type.toLowerCase())) {
        types.add(_ExpenseCatalogItem(en: type, ar: ''));
        changed = true;
      }
    }
    if (changed) _saveCatalog();
  }

  Future<void> _saveCatalog() async {
    await LocalDatabaseService.setString(_categoriesKey,
        jsonEncode(_categories.map((item) => item.toJson()).toList()));
    await LocalDatabaseService.setString(
        _typesKey,
        jsonEncode(_typesByCategory.map((key, value) =>
            MapEntry(key, value.map((item) => item.toJson()).toList()))));
  }

  List<_ExpenseCatalogItem> get _activeCategories =>
      (_categories.where((item) => !item.archived).toList()
        ..sort((a, b) => a.en.compareTo(b.en)));

  List<_ExpenseCatalogItem> get _activeTypes {
    final category = selectedCategory;
    if (category == null) return const <_ExpenseCatalogItem>[];
    return ((_typesByCategory[category] ?? const <_ExpenseCatalogItem>[])
        .where((item) => !item.archived)
        .toList()
      ..sort((a, b) => a.en.compareTo(b.en)));
  }

  String? _normalizeInitialCategory(String? raw) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? _normalizeInitialType(String? raw, String? category) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 700);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(widget.expense == null
          ? tr.text('add_expense')
          : tr.text('edit_expense')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: InputDecoration(
                    labelText: tr.text('expense_category'),
                    helperText: tr.text('expense_category_helper'),
                    suffixIcon: IconButton(
                      tooltip: tr.text('manage_expense_categories'),
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => _openCategoryManager(context),
                    ),
                  ),
                  items: _activeCategories
                      .map((item) => DropdownMenuItem(
                          value: item.en, child: Text(item.label(context))))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedCategory = value;
                    selectedExpenseType = null;
                  }),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr.text('required')
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      _activeTypes.any((item) => item.en == selectedExpenseType)
                          ? selectedExpenseType
                          : null,
                  decoration: InputDecoration(
                    labelText: tr.text('expense_type'),
                    helperText: selectedCategory == null
                        ? tr.text('select_expense_category_first')
                        : tr.text('expense_type_helper'),
                    suffixIcon: IconButton(
                      tooltip: tr.text('manage_expense_types'),
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: selectedCategory == null
                          ? null
                          : () => _openTypeManager(context),
                    ),
                  ),
                  disabledHint: Text(tr.text('select_expense_category_first')),
                  items: _activeTypes
                      .map((item) => DropdownMenuItem(
                          value: item.en, child: Text(item.label(context))))
                      .toList(),
                  onChanged: selectedCategory == null
                      ? null
                      : (value) => setState(() => selectedExpenseType = value),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr.text('required')
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: amountController,
                        decoration:
                            InputDecoration(labelText: tr.text('amount')),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}$'))
                        ],
                        validator: _amountValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: amountCurrency,
                        decoration:
                            InputDecoration(labelText: tr.text('currency')),
                        items: const [
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                        ],
                        onChanged: (value) =>
                            setState(() => amountCurrency = value ?? 'USD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: tr.text('date'),
                        prefixIcon: const Icon(Icons.calendar_today_outlined)),
                    child: Text(DateFormat('yyyy-MM-dd HH:mm')
                        .format(selectedDate.toLocal())),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: tr.text('expense_description'),
                    helperText: tr.text('expense_description_helper'),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final originalAmount = double.parse(amountController.text.trim());
            final amount = toUsdReferencePrice(
                originalAmount, amountCurrency, widget.storeProfile);
            Navigator.pop(
              context,
              Expense(
                id: widget.expense?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                title: selectedExpenseType!.trim(),
                category: selectedCategory!.trim(),
                amount: amount,
                originalAmount: originalAmount,
                originalCurrency: amountCurrency,
                exchangeRateAtEntry: widget.storeProfile.usdToLbpRate,
                date: selectedDate,
                notes: notesController.text.trim(),
                status: widget.expense?.status ?? 'Draft',
                cancelReason: widget.expense?.cancelReason ?? '',
                cancelledByDeviceId: widget.expense?.cancelledByDeviceId ?? '',
                cancelledAt: widget.expense?.cancelledAt,
                createdAt: widget.expense?.createdAt,
                updatedAt: widget.expense?.updatedAt,
                deletedAt: widget.expense?.deletedAt,
                deviceId: widget.expense?.deviceId ?? '',
                syncStatus: widget.expense?.syncStatus ?? 'pending',
                storeId: widget.expense?.storeId ?? '',
                branchId: widget.expense?.branchId ?? '',
                version: widget.expense?.version ?? 1,
                lastModifiedByDeviceId:
                    widget.expense?.lastModifiedByDeviceId ?? '',
              ),
            );
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }

  Future<void> _openCategoryManager(BuildContext context) async {
    final changed = await _showCatalogManager(
      context: context,
      title: AppLocalizations.of(context).text('manage_expense_categories'),
      items: _categories,
      isUsed: (name) => widget.existingExpenses.any((expense) =>
          expense.category.trim().toLowerCase() == name.toLowerCase()),
      onRenamed: (oldName, newName) {
        final existingTypes =
            _typesByCategory.remove(oldName) ?? <_ExpenseCatalogItem>[];
        _typesByCategory[newName] = existingTypes;
        if (selectedCategory == oldName) selectedCategory = newName;
      },
    );
    if (changed) {
      await _saveCatalog();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openTypeManager(BuildContext context) async {
    final category = selectedCategory;
    if (category == null) return;
    final items =
        _typesByCategory.putIfAbsent(category, () => <_ExpenseCatalogItem>[]);
    final changed = await _showCatalogManager(
      context: context,
      title:
          '${AppLocalizations.of(context).text('manage_expense_types')} - $category',
      items: items,
      isUsed: (name) => widget.existingExpenses.any((expense) =>
          expense.category.trim().toLowerCase() == category.toLowerCase() &&
          expense.title.trim().toLowerCase() == name.toLowerCase()),
      onRenamed: (oldName, newName) {
        if (selectedExpenseType == oldName) selectedExpenseType = newName;
      },
    );
    if (changed) {
      await _saveCatalog();
      if (mounted) setState(() {});
    }
  }

  Future<bool> _showCatalogManager({
    required BuildContext context,
    required String title,
    required List<_ExpenseCatalogItem> items,
    required bool Function(String name) isUsed,
    required void Function(String oldName, String newName) onRenamed,
  }) async {
    var changed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final active = items.where((item) => !item.archived).toList()
            ..sort((a, b) => a.en.compareTo(b.en));
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: active.isEmpty
                  ? Text(AppLocalizations.of(dialogContext).text('no_items'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: active.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = active[index];
                        return ListTile(
                          title: Text(item.label(context)),
                          subtitle: Text(item.en),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip:
                                    AppLocalizations.of(context).text('edit'),
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final edited = await _showCatalogItemEditor(
                                      context, item);
                                  if (edited == null) return;
                                  if (_nameExists(items, edited.en,
                                      except: item.en)) return;
                                  final position = items.indexOf(item);
                                  if (position >= 0) {
                                    items[position] = edited;
                                    onRenamed(item.en, edited.en);
                                    changed = true;
                                    setDialogState(() {});
                                  }
                                },
                              ),
                              IconButton(
                                tooltip:
                                    AppLocalizations.of(context).text('delete'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  final position = items.indexOf(item);
                                  if (position < 0) return;
                                  if (isUsed(item.en)) {
                                    items[position] =
                                        item.copyWith(archived: true);
                                  } else {
                                    items.removeAt(position);
                                  }
                                  changed = true;
                                  setDialogState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final added =
                      await _showCatalogItemEditor(dialogContext, null);
                  if (added == null) return;
                  if (_nameExists(items, added.en)) return;
                  items.add(added);
                  changed = true;
                  setDialogState(() {});
                },
                child: Text(AppLocalizations.of(dialogContext).text('add')),
              ),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(dialogContext).text('done'))),
            ],
          );
        },
      ),
    );
    return changed;
  }

  bool _nameExists(List<_ExpenseCatalogItem> items, String name,
          {String? except}) =>
      items.any((item) =>
          !item.archived &&
          item.en.toLowerCase() == name.toLowerCase() &&
          item.en.toLowerCase() != (except ?? '').toLowerCase());

  Future<_ExpenseCatalogItem?> _showCatalogItemEditor(
      BuildContext context, _ExpenseCatalogItem? item) async {
    final enController = TextEditingController(text: item?.en ?? '');
    final arController = TextEditingController(text: item?.ar ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<_ExpenseCatalogItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null
            ? AppLocalizations.of(context).text('add')
            : AppLocalizations.of(context).text('edit')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: enController,
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context).text('english_name')),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? AppLocalizations.of(context).text('required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: arController,
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context).text('arabic_name')),
                textDirection: ui.TextDirection.rtl,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                  context,
                  _ExpenseCatalogItem(
                      en: enController.text.trim(),
                      ar: arController.text.trim(),
                      archived: item?.archived ?? false));
            },
            child: Text(AppLocalizations.of(context).text('save')),
          ),
        ],
      ),
    );
    enController.dispose();
    arController.dispose();
    return result;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
    if (!mounted) return;
    setState(() {
      selectedDate = DateTime(date.year, date.month, date.day,
          time?.hour ?? selectedDate.hour, time?.minute ?? selectedDate.minute);
    });
  }

  String? _amountValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return AppLocalizations.of(context).text('required');
    final number = double.tryParse(trimmed);
    if (number == null || number <= 0)
      return AppLocalizations.of(context).text('invalid_number');
    return null;
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard(
      {required this.width,
      required this.title,
      required this.value,
      required this.icon});

  final double width;
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
    );
  }
}
