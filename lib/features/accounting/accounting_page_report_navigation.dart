part of 'accounting_page.dart';

enum _AccountingReportRangeMode {
  today,
  week,
  month,
  year,
  accountingPeriod,
  custom,
}

class _AccountingReportRange {
  const _AccountingReportRange({
    required this.from,
    required this.to,
    required this.label,
  });

  final DateTime from;
  final DateTime to;
  final String label;

  String get cacheKey => '${from.toIso8601String()}|${to.toIso8601String()}';
}

class _ReportsAccountingGroup extends StatefulWidget {
  const _ReportsAccountingGroup({required this.store, required this.query});

  final AppStore store;
  final String query;

  @override
  State<_ReportsAccountingGroup> createState() =>
      _ReportsAccountingGroupState();
}

class _ReportsAccountingGroupState extends State<_ReportsAccountingGroup> {
  _AccountingReportRangeMode _mode = _AccountingReportRangeMode.month;
  DateTime? _customFrom;
  DateTime? _customTo;
  List<AdvancedAccountingItem> _accountingPeriods =
      const <AdvancedAccountingItem>[];
  String _selectedAccountingPeriodId = '';

  @override
  void initState() {
    super.initState();
    _loadAccountingPeriods();
  }

  Future<void> _loadAccountingPeriods() async {
    try {
      final periods = (await AccountingService.listAccountingPeriods())
          .where((period) =>
              DateTime.tryParse(period.accountCode) != null &&
              DateTime.tryParse(period.accountName) != null)
          .toList(growable: false);
      final now = DateTime.now().toLocal();
      AdvancedAccountingItem? current;
      for (final period in periods) {
        final start = DateTime.parse(period.accountCode).toLocal();
        final end = DateTime.parse(period.accountName).toLocal();
        final containsNow =
            !now.isBefore(_startOfDay(start)) && !now.isAfter(_endOfDay(end));
        final isOpen = period.type.trim().toLowerCase() == 'open';
        if (containsNow && isOpen) {
          current = period;
          break;
        }
        if (current == null && containsNow) current = period;
      }
      if (!mounted) return;
      setState(() {
        _accountingPeriods = periods;
        final selected = current ?? (periods.isEmpty ? null : periods.first);
        _selectedAccountingPeriodId = selected?.id ?? '';
        if (current != null && _mode == _AccountingReportRangeMode.month) {
          _mode = _AccountingReportRangeMode.accountingPeriod;
        }
      });
    } catch (_) {
      // Date presets remain usable even if accounting-period metadata is unavailable.
    }
  }

  AdvancedAccountingItem? get _selectedAccountingPeriod {
    for (final period in _accountingPeriods) {
      if (period.id == _selectedAccountingPeriodId) return period;
    }
    return _accountingPeriods.isEmpty ? null : _accountingPeriods.first;
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);

  _AccountingReportRange _effectiveRange(BuildContext context) {
    final now = DateTime.now().toLocal();
    switch (_mode) {
      case _AccountingReportRangeMode.today:
        return _AccountingReportRange(
          from: _startOfDay(now),
          to: _endOfDay(now),
          label: _accountingUiText(context, 'اليوم', 'Today', 'Aujourd’hui'),
        );
      case _AccountingReportRangeMode.week:
        final today = _startOfDay(now);
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return _AccountingReportRange(
          from: start,
          to: _endOfDay(end),
          label: _accountingUiText(
              context, 'هذا الأسبوع', 'This week', 'Cette semaine'),
        );
      case _AccountingReportRangeMode.month:
        final from = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return _AccountingReportRange(
          from: from,
          to: nextMonth.subtract(const Duration(microseconds: 1)),
          label:
              _accountingUiText(context, 'هذا الشهر', 'This month', 'Ce mois'),
        );
      case _AccountingReportRangeMode.year:
        return _AccountingReportRange(
          from: DateTime(now.year, 1, 1),
          to: DateTime(now.year, 12, 31, 23, 59, 59, 999, 999),
          label: _accountingUiText(
              context, 'هذه السنة', 'This year', 'Cette année'),
        );
      case _AccountingReportRangeMode.accountingPeriod:
        final period = _selectedAccountingPeriod;
        final start = DateTime.tryParse(period?.accountCode ?? '')?.toLocal();
        final end = DateTime.tryParse(period?.accountName ?? '')?.toLocal();
        if (period != null && start != null && end != null) {
          return _AccountingReportRange(
            from: _startOfDay(start),
            to: _endOfDay(end),
            label: period.name.trim().isEmpty
                ? _accountingUiText(context, 'فترة محاسبية',
                    'Accounting period', 'Période comptable')
                : period.name,
          );
        }
        final monthStart = DateTime(now.year, now.month, 1);
        return _AccountingReportRange(
          from: monthStart,
          to: _endOfDay(now),
          label:
              _accountingUiText(context, 'هذا الشهر', 'This month', 'Ce mois'),
        );
      case _AccountingReportRangeMode.custom:
        final from = _customFrom ?? DateTime(now.year, now.month, 1);
        final to = _customTo ?? now;
        return _AccountingReportRange(
          from: _startOfDay(from),
          to: _endOfDay(to),
          label: _accountingUiText(
              context, 'فترة مخصصة', 'Custom range', 'Période personnalisée'),
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now().toLocal();
    final initialStart = _customFrom ?? DateTime(now.year, now.month, 1);
    final initialEnd = _customTo ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customFrom = picked.start;
      _customTo = picked.end;
      _mode = _AccountingReportRangeMode.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final range = _effectiveRange(context);
    return DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.balance_outlined),
                  text: tr.text('trial_balance')),
              Tab(
                  icon: const Icon(Icons.trending_up_outlined),
                  text: tr.text('income_statement')),
              Tab(
                  icon: const Icon(Icons.account_balance_outlined),
                  text: tr.text('balance_sheet')),
              Tab(
                  icon: const Icon(Icons.waterfall_chart_outlined),
                  text: tr.text('cash_flow_statement')),
              Tab(
                  icon: const Icon(Icons.receipt_long_outlined),
                  text: tr.text('tax_report')),
              Tab(
                  icon: const Icon(Icons.inventory_2_outlined),
                  text: tr.text('inventory')),
            ],
          ),
          const SizedBox(height: 8),
          _AccountingReportRangeBar(
            mode: _mode,
            range: range,
            accountingPeriods: _accountingPeriods,
            selectedAccountingPeriodId: _selectedAccountingPeriodId,
            onModeChanged: (mode) {
              if (mode == _AccountingReportRangeMode.custom) {
                _pickCustomRange();
                return;
              }
              setState(() => _mode = mode);
            },
            onAccountingPeriodChanged: (periodId) {
              setState(() {
                _selectedAccountingPeriodId = periodId;
                _mode = _AccountingReportRangeMode.accountingPeriod;
              });
            },
            onPickCustom: _pickCustomRange,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                final rangeToken = range.cacheKey;
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      cacheToken: 'trial|$rangeToken',
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('trial_balance'),
                        child: _TrialBalanceTab(
                          store: widget.store,
                          query: widget.query,
                          from: range.from,
                          to: range.to,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      cacheToken: 'income|$rangeToken',
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('income_statement'),
                        child: _IncomeStatementTab(
                          store: widget.store,
                          from: range.from,
                          to: range.to,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      cacheToken: 'balance|$rangeToken',
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('balance_sheet'),
                        child: _BalanceSheetTab(
                          store: widget.store,
                          asOf: range.to,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 3,
                      cacheToken: 'cashflow|$rangeToken',
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('cash_flow_statement'),
                        child: _CashFlowStatementTab(
                          store: widget.store,
                          from: range.from,
                          to: range.to,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 4,
                      cacheToken: 'tax|$rangeToken',
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('tax_report'),
                        child: _TaxReportTab(
                          store: widget.store,
                          from: range.from,
                          to: range.to,
                        ),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 5,
                      builder: (_) => _AccountingPrintablePage(
                        store: widget.store,
                        title: tr.text('inventory'),
                        child: _InventoryManufacturingReportsTab(
                          store: widget.store,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingReportRangeBar extends StatelessWidget {
  const _AccountingReportRangeBar({
    required this.mode,
    required this.range,
    required this.accountingPeriods,
    required this.selectedAccountingPeriodId,
    required this.onModeChanged,
    required this.onAccountingPeriodChanged,
    required this.onPickCustom,
  });

  final _AccountingReportRangeMode mode;
  final _AccountingReportRange range;
  final List<AdvancedAccountingItem> accountingPeriods;
  final String selectedAccountingPeriodId;
  final ValueChanged<_AccountingReportRangeMode> onModeChanged;
  final ValueChanged<String> onAccountingPeriodChanged;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    final hasAccountingPeriods = accountingPeriods.isNotEmpty;
    final effectiveMode = mode == _AccountingReportRangeMode.accountingPeriod &&
            !hasAccountingPeriods
        ? _AccountingReportRangeMode.month
        : mode;
    final dateRangeText = '${_dateText(range.from)} → ${_dateText(range.to)}';
    final selectedPeriodExists = accountingPeriods
        .any((period) => period.id == selectedAccountingPeriodId);
    final selectedPeriodValue = selectedPeriodExists
        ? selectedAccountingPeriodId
        : (accountingPeriods.isEmpty ? null : accountingPeriods.first.id);

    final modeSelector = DropdownButton<_AccountingReportRangeMode>(
      value: effectiveMode,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
          value: _AccountingReportRangeMode.today,
          child:
              Text(_accountingUiText(context, 'اليوم', 'Today', 'Aujourd’hui')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.week,
          child: Text(_accountingUiText(
              context, 'هذا الأسبوع', 'This week', 'Cette semaine')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.month,
          child: Text(
              _accountingUiText(context, 'هذا الشهر', 'This month', 'Ce mois')),
        ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.year,
          child: Text(_accountingUiText(
              context, 'هذه السنة', 'This year', 'Cette année')),
        ),
        if (hasAccountingPeriods)
          DropdownMenuItem(
            value: _AccountingReportRangeMode.accountingPeriod,
            child: Text(_accountingUiText(context, 'فترة محاسبية',
                'Accounting period', 'Période comptable')),
          ),
        DropdownMenuItem(
          value: _AccountingReportRangeMode.custom,
          child: Text(_accountingUiText(
              context, 'فترة مخصصة', 'Custom range', 'Période personnalisée')),
        ),
      ],
      onChanged: (value) {
        if (value != null) onModeChanged(value);
      },
    );

    final periodSelector =
        effectiveMode == _AccountingReportRangeMode.accountingPeriod &&
                selectedPeriodValue != null
            ? DropdownButton<String>(
                value: selectedPeriodValue,
                underline: const SizedBox.shrink(),
                items: [
                  for (final period in accountingPeriods)
                    DropdownMenuItem(
                      value: period.id,
                      child: Text(
                        _accountingPeriodLabel(context, period),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onAccountingPeriodChanged(value);
                },
              )
            : null;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final details = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_outlined, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${range.label} • $dateRangeText',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (effectiveMode == _AccountingReportRangeMode.custom) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: _accountingUiText(context, 'تغيير الفترة',
                          'Change range', 'Modifier la période'),
                      onPressed: onPickCustom,
                      icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                    ),
                  ],
                ],
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modeSelector,
                    if (periodSelector != null) ...[
                      const SizedBox(height: 4),
                      periodSelector,
                    ],
                    const SizedBox(height: 6),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  Text(
                    _accountingUiText(context, 'فترة التقرير:',
                        'Report period:', 'Période :'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  modeSelector,
                  if (periodSelector != null) ...[
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: periodSelector,
                    ),
                  ],
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _accountingPeriodLabel(
    BuildContext context, AdvancedAccountingItem period) {
  final name = period.name.trim();
  if (name.isNotEmpty) return name;
  final start = DateTime.tryParse(period.accountCode)?.toLocal();
  final end = DateTime.tryParse(period.accountName)?.toLocal();
  if (start != null && end != null) {
    return '${_dateText(start)} → ${_dateText(end)}';
  }
  return _accountingUiText(
      context, 'فترة محاسبية', 'Accounting period', 'Période comptable');
}

String _accountingUiText(
    BuildContext context, String ar, String en, String fr) {
  final language = Localizations.localeOf(context).languageCode;
  if (language == 'ar') return ar;
  if (language == 'fr') return fr;
  return en;
}

String _topSectionSubtitle(BuildContext context, int index) {
  switch (index) {
    case 0:
      return _accountingUiText(
          context,
          'العملاء والموردون وأعمار الديون',
          'Customers, suppliers and aging',
          'Clients, fournisseurs et échéances');
    case 1:
      return _accountingUiText(
          context,
          'القيود اليومية ودفتر الأستاذ ودليل الحسابات',
          'Journal, general ledger and chart of accounts',
          'Journal, grand livre et plan comptable');
    case 2:
      return _accountingUiText(
          context,
          'حركة النقد والبنوك والرقابة النقدية',
          'Cash, banks and treasury monitoring',
          'Trésorerie, banques et suivi');
    case 3:
      return _accountingUiText(
          context,
          'التقارير المالية الرسمية حسب الفترة',
          'Period-based financial statements',
          'Rapports financiers par période');
    case 4:
      return _accountingUiText(
          context,
          'إدارة الفترات والربط والإعدادات المحاسبية',
          'Periods, mappings and accounting administration',
          'Périodes, rattachements et administration');
    default:
      return _accountingUiText(
          context, 'المحاسبة', 'Accounting', 'Comptabilité');
  }
}

class _SettingsAccountingGroup extends StatelessWidget {
  const _SettingsAccountingGroup({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingGroupTabs(
            tabs: [
              Tab(
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  text: _accountingUiText(
                    context,
                    'الإدارة المحاسبية',
                    'Accounting administration',
                    'Administration comptable',
                  )),
              const Tab(
                  icon: Icon(Icons.account_tree_outlined),
                  text: 'ربط الحسابات'),
              Tab(
                  icon: const Icon(Icons.settings_outlined),
                  text: tr.text('settings')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return TabBarView(
                  children: [
                    _LazyTabPane(
                      controller: controller,
                      index: 0,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: _accountingUiText(
                          context,
                          'الإدارة المحاسبية',
                          'Accounting administration',
                          'Administration comptable',
                        ),
                        child: _AdvancedAccountingTab(store: store),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 1,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: _accountingUiText(context, 'ربط الحسابات',
                            'Account mapping', 'Rattachement des comptes'),
                        child: _AccountingRolesTab(store: store),
                      ),
                    ),
                    _LazyTabPane(
                      controller: controller,
                      index: 2,
                      builder: (_) => _AccountingPrintablePage(
                        store: store,
                        title: tr.text('settings'),
                        child: _AccountingSettingsTab(store: store),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingGroupTabs extends StatelessWidget {
  const _AccountingGroupTabs({required this.tabs});

  final List<Widget> tabs;

  Widget _compactTab(Widget tab) {
    if (tab is! Tab || tab.text == null) return tab;
    return Tab(
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tab.icon != null) ...[
            IconTheme(
              data: const IconThemeData(size: 17),
              child: tab.icon!,
            ),
            const SizedBox(width: 5),
          ],
          Text(tab.text!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: TabBar(
          isScrollable: true,
          labelStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          tabs: tabs.map(_compactTab).toList(growable: false),
        ),
      ),
    );
  }
}

class _LazyTabPane extends StatefulWidget {
  const _LazyTabPane({
    required this.controller,
    required this.index,
    required this.builder,
    this.cacheToken,
  });

  final TabController controller;
  final int index;
  final WidgetBuilder builder;
  final Object? cacheToken;

  @override
  State<_LazyTabPane> createState() => _LazyTabPaneState();
}

class _LazyTabPaneState extends State<_LazyTabPane> {
  Widget? _builtChild;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTabChanged);
  }

  @override
  void didUpdateWidget(covariant _LazyTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTabChanged);
      widget.controller.addListener(_handleTabChanged);
    }
    if (oldWidget.cacheToken != widget.cacheToken) {
      _builtChild = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTabChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.index == widget.index;
    if (active && _builtChild == null) {
      _builtChild = widget.builder(context);
    }
    return _builtChild ?? const SizedBox.expand();
  }
}

class _AccountingPrintablePage extends StatefulWidget {
  const _AccountingPrintablePage({
    required this.store,
    required this.title,
    required this.child,
  });

  final AppStore store;
  final String title;
  final Widget child;

  @override
  State<_AccountingPrintablePage> createState() =>
      _AccountingPrintablePageState();
}

class _AccountingPrintablePageState extends State<_AccountingPrintablePage> {
  final GlobalKey _printBoundaryKey = GlobalKey();
  bool _printing = false;

  Future<void> _printCurrentPage() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _printBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Accounting page is not ready for printing.');
      }
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final captureRatio = devicePixelRatio.clamp(1.0, 2.0).toDouble();
      final image = await boundary.toImage(pixelRatio: captureRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Could not capture the accounting page.');
      }
      final imageBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      if (!mounted) return;
      final pdfImage = pw.MemoryImage(Uint8List.fromList(imageBytes));
      await PrintService.printPdf(
        profile: widget.store.storeProfile,
        documentKey: PrintDocumentKeys.accountingPage,
        context: context,
        bytesBuilder: (selection) async {
          final pdf = pw.Document();
          final pageFormat = selection.format == PrintPaperFormats.a4 &&
                  image.width >= image.height
              ? PdfPageFormat.a4.landscape
              : PrintService.pageFormatFor(
                  selection.format,
                  fallback: PdfPageFormat.a4,
                );
          pdf.addPage(
            pw.Page(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(18),
              build: (_) => pw.Center(
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
          return Uint8List.fromList(await pdf.save());
        },
        name: widget.title.trim().isEmpty ? 'accounting' : widget.title.trim(),
        defaultFormat: PdfPageFormat.a4,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _accountingUiText(
              context,
              'تعذر تجهيز الصفحة للطباعة: $error',
              'Could not prepare this page for printing: $error',
              'Impossible de préparer cette page pour l’impression : $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: _printBoundaryKey,
          child: widget.child,
        ),
        PositionedDirectional(
          top: 4,
          end: 4,
          child: Material(
            color: Colors.transparent,
            child: IconButton.filledTonal(
              tooltip: AppLocalizations.of(context).text('print'),
              onPressed: _printing ? null : _printCurrentPage,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              icon: _printing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountingSearchField extends StatelessWidget {
  const _AccountingSearchField({required this.controller, required this.query});

  final TextEditingController controller;
  final String query;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        prefixIcon: const Icon(Icons.search),
        labelText: AppLocalizations.of(context).text('search_accounts'),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close), onPressed: controller.clear),
      ),
    );
  }
}
