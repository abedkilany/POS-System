// ignore_for_file: curly_braces_in_flow_control_structures
part of 'expenses_page.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String query = '';
  String statusFilter = 'all';
  Timer? _expenseRevealTimer;
  int _visibleExpenseCount = 100;
  int _expenseRevealTargetCount = 0;
  Future<_ExpenseQueryResult?>? _expenseQueryFuture;
  String _expenseQueryFutureKey = '';
  final RevisionKeyCache<List<Expense>> _filteredExpensesCache =
      RevisionKeyCache<List<Expense>>();
  final RevisionKeyCache<double> _filteredTotalCache =
      RevisionKeyCache<double>();

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _expenseRevealTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _expenseQueryFuture = null;
      _expenseQueryFutureKey = '';
      _filteredExpensesCache.invalidate();
      _filteredTotalCache.invalidate();
      _resetExpenseReveal();
    }
  }

  void _resetExpenseReveal() {
    _expenseRevealTimer?.cancel();
    _expenseRevealTimer = null;
    _visibleExpenseCount = 100;
    _expenseRevealTargetCount = 0;
  }

  void _syncExpenseReveal(int totalCount) {
    _expenseRevealTargetCount = totalCount;
    if (_visibleExpenseCount > totalCount) {
      _visibleExpenseCount = totalCount;
    }
    if (_visibleExpenseCount >= totalCount) {
      _expenseRevealTimer?.cancel();
      _expenseRevealTimer = null;
      return;
    }
    _expenseRevealTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        _expenseRevealTimer = null;
        return;
      }
      if (_visibleExpenseCount >= _expenseRevealTargetCount) {
        timer.cancel();
        _expenseRevealTimer = null;
        return;
      }
      setState(() {
        _visibleExpenseCount = math.min(
          _expenseRevealTargetCount,
          _visibleExpenseCount + 100,
        );
      });
      if (_visibleExpenseCount >= _expenseRevealTargetCount) {
        timer.cancel();
        _expenseRevealTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.canViewExpenses) {
      return _AccessDeniedScaffold(
        title: tr.text('expenses'),
        message: tr.text('no_access_expense_records'),
      );
    }
    if (!widget.store.runtime.isCoreDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final normalizedQuery = query.trim().toLowerCase();
    final overview = widget.store.commerce.expensesOverview;
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_ExpenseQueryResult?>(
        future: _queryExpensesFromSqlite(normalizedQuery),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildExpensesView(
              context,
              tr,
              overview: overview,
              expenses: result.items,
              totalCount: result.totalCount,
              filteredTotal: result.filteredPostedTotal,
              normalizedQuery: normalizedQuery,
              loading: snapshot.connectionState == ConnectionState.waiting &&
                  result.items.isEmpty,
              onLoadMore: result.hasMore
                  ? () => _loadMoreExpenses(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildExpensesView(
              context,
              tr,
              overview: overview,
              expenses: const <Expense>[],
              totalCount: 0,
              filteredTotal: 0,
              normalizedQuery: normalizedQuery,
              loading: true,
            );
          }
          return _buildExpensesFromMemory(
            context,
            tr,
            overview,
            normalizedQuery,
          );
        },
      );
    }
    return _buildExpensesFromMemory(
      context,
      tr,
      overview,
      normalizedQuery,
    );
  }

  Widget _buildExpensesFromMemory(
    BuildContext context,
    AppLocalizations tr,
    ExpensesOverview overview,
    String normalizedQuery,
  ) {
    final cacheKey = '$statusFilter|$normalizedQuery';
    final allExpenses = widget.store.commerce.expenses;
    final useDefaultView = statusFilter == 'all' && normalizedQuery.isEmpty;
    final expenses = useDefaultView
        ? allExpenses
        : _filteredExpensesCache.getOrCompute(
            widget.store.commerce.expensesRevision,
            cacheKey,
            () => allExpenses.where((expense) {
              final matchesStatus = statusFilter == 'all' ||
                  (statusFilter == 'draft' && expense.isDraft) ||
                  (statusFilter == 'posted' && expense.isPosted) ||
                  (statusFilter == 'cancelled' && expense.isCancelled);
              if (!matchesStatus) return false;
              if (normalizedQuery.isEmpty) return true;
              return expense.searchText.contains(normalizedQuery);
            }).toList(growable: false),
          );
    final filteredTotal = useDefaultView
        ? overview.totalExpensesAmount
        : _filteredTotalCache.getOrCompute(
            widget.store.commerce.expensesRevision,
            cacheKey,
            () => expenses
                .where((expense) => expense.isPosted)
                .fold<double>(0, (sum, expense) => sum + expense.amount),
          );
    _syncExpenseReveal(expenses.length);
    final visibleExpenses =
        expenses.take(math.min(_visibleExpenseCount, expenses.length)).toList(
              growable: false,
            );
    return _buildExpensesView(
      context,
      tr,
      overview: overview,
      expenses: visibleExpenses,
      totalCount: expenses.length,
      filteredTotal: filteredTotal,
      normalizedQuery: normalizedQuery,
    );
  }

  Future<_ExpenseQueryResult?> _queryExpensesFromSqlite(
    String normalizedQuery,
  ) {
    final limit = math.max(1, _visibleExpenseCount);
    final key =
        '${widget.store.commerce.expensesRevision}|$statusFilter|$normalizedQuery|$limit';
    if (_expenseQueryFuture == null || _expenseQueryFutureKey != key) {
      _expenseQueryFutureKey = key;
      _expenseQueryFuture = () async {
        final page = await LocalDatabaseService.queryExpensesFromSqlite(
          query: normalizedQuery,
          status: statusFilter,
          limit: limit,
        );
        if (page == null) return null;
        final filteredPostedTotal = normalizedQuery.isEmpty
            ? widget.store.commerce.expensesOverview.totalExpensesAmount
            : await LocalDatabaseService.sumPostedExpensesFromSqlite(
                  query: normalizedQuery,
                  status: statusFilter,
                ) ??
                0;
        return _ExpenseQueryResult(
          items: page.items,
          totalCount: page.totalCount,
          filteredPostedTotal: filteredPostedTotal,
        );
      }();
    }
    return _expenseQueryFuture!;
  }

  void _loadMoreExpenses(int totalCount) {
    setState(() {
      _expenseRevealTimer?.cancel();
      _expenseRevealTimer = null;
      _visibleExpenseCount = math.min(totalCount, _visibleExpenseCount + 100);
    });
  }

  Widget _buildExpensesView(
    BuildContext context,
    AppLocalizations tr, {
    required ExpensesOverview overview,
    required List<Expense> expenses,
    required int totalCount,
    required double filteredTotal,
    required String normalizedQuery,
    bool loading = false,
    VoidCallback? onLoadMore,
  }) {
    final hasLoadMore = onLoadMore != null;
    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: tr.text('expenses'),
            subtitle: tr.text('expenses_page_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                PageDataLoadIndicator(
                  loadedCount: expenses.length,
                  totalCount: totalCount,
                ),
                OutlinedButton.icon(
                  onPressed: () => printExpenseStatementForPeriod(
                    context: context,
                    store: widget.store,
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(tr.text('print_expense_statement')),
                ),
                FilledButton.icon(
                  onPressed: widget.store.security.canManageExpenses
                      ? () => _openExpenseForm(context)
                      : null,
                  icon: const Icon(Icons.add_card_outlined),
                  label: Text(tr.text('add_expense')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = VentioResponsive.columnsForWidth(
                  constraints.maxWidth,
                  mobile: 1,
                  tablet: 3,
                  desktop: 3);
              final gap = VentioResponsive.gap(context);
              final cardWidth =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _MiniCard(
                      width: cardWidth,
                      title: tr.text('total'),
                      value: formatUsdReferenceAmount(
                          overview.totalExpensesAmount,
                          widget.store.runtime.profile),
                      icon: Icons.payments_outlined),
                  _MiniCard(
                      width: cardWidth,
                      title: tr.text('expenses_count'),
                      value: '${overview.totalCount}',
                      icon: Icons.receipt_outlined),
                  _MiniCard(
                      width: cardWidth,
                      title: tr.text('category'),
                      value: '${overview.categoryCount}',
                      icon: Icons.category_outlined),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: tr.text('search_expense'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() {
                            query = '';
                            _resetExpenseReveal();
                          }),
                      icon: const Icon(Icons.close)),
            ),
            onChanged: (value) => setState(() {
              query = value;
              _resetExpenseReveal();
            }),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                    label: Text('${tr.text('all')} (${overview.totalCount})'),
                    selected: statusFilter == 'all',
                    onSelected: (_) => setState(() {
                          statusFilter = 'all';
                          _resetExpenseReveal();
                        })),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: Text('${tr.text('draft')} (${overview.draftCount})'),
                    selected: statusFilter == 'draft',
                    onSelected: (_) => setState(() {
                          statusFilter = 'draft';
                          _resetExpenseReveal();
                        })),
                const SizedBox(width: 8),
                ChoiceChip(
                    label:
                        Text('${tr.text('posted')} (${overview.postedCount})'),
                    selected: statusFilter == 'posted',
                    onSelected: (_) => setState(() {
                          statusFilter = 'posted';
                          _resetExpenseReveal();
                        })),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: Text(
                        '${tr.text('cancelled')} (${overview.cancelledCount})'),
                    selected: statusFilter == 'cancelled',
                    onSelected: (_) => setState(() {
                          statusFilter = 'cancelled';
                          _resetExpenseReveal();
                        })),
              ],
            ),
          ),
          if (normalizedQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
                '${tr.text('total')}: ${formatUsdReferenceAmount(filteredTotal, widget.store.runtime.profile)}',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : totalCount == 0
                    ? EmptyStateCard(
                        icon: Icons.payments_outlined,
                        title: tr.text('no_expenses'),
                        subtitle: tr.text('no_expenses_desc'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final rowExtent =
                              constraints.maxWidth < 620 ? 188.0 : 168.0;
                          return ListView.builder(
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(2000),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemExtent: rowExtent,
                            itemCount: expenses.length + (hasLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= expenses.length) {
                                return Center(
                                  child: TextButton.icon(
                                    onPressed: onLoadMore,
                                    icon: const Icon(Icons.expand_more),
                                    label: Text(
                                      '${tr.text('more')} '
                                      '(${expenses.length}/$totalCount)',
                                    ),
                                  ),
                                );
                              }
                              final expense = expenses[index];
                              return _ExpenseCard(
                                expense: expense,
                                storeProfile: widget.store.runtime.profile,
                                onPrint: () => _printExpense(context, expense),
                                onEdit: (expense.isDraft || expense.isPosted) &&
                                        widget.store.security.canManageExpenses
                                    ? () => _openExpenseForm(context,
                                        expense: expense)
                                    : null,
                                onPost: expense.isDraft &&
                                        widget.store.security
                                            .hasAnyPermission(<String>{
                                          AppPermission.expensesApprove,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _postExpense(context, expense)
                                    : null,
                                onCancel: expense.isPosted &&
                                        widget.store.security
                                            .hasAnyPermission(<String>{
                                          AppPermission.expensesCancel,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _cancelExpense(context, expense)
                                    : null,
                                onDeleteDraft: expense.isDraft &&
                                        widget.store.security
                                            .hasAnyPermission(<String>{
                                          AppPermission.expensesDelete,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _deleteExpense(context, expense)
                                    : null,
                                onPermanentDelete: null,
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(BuildContext context, Expense expense) async {
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.expensesDelete,
      AppPermission.expensesManage,
    })) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text(expense.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.commerce.deleteDraftExpense(expense.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr.text('expense_deleted').replaceAll('{title}', expense.title),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _postExpense(BuildContext context, Expense expense) async {
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.expensesApprove,
      AppPermission.expensesManage,
    })) return;
    final tr = AppLocalizations.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final cashAmountController = TextEditingController(
      text: expense.amount.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    final settlement = await showDialog<_ExpensePostingSelection>(
      context: context,
      builder: (dialogContext) {
        var paymentMode = 'cash';
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(isArabic
                ? 'تحديد حالة الصرف'
                : 'Select expense payment status'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isArabic
                          ? 'كيف تريد اعتماد هذا المصروف؟'
                          : 'How do you want to post this expense?',
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<String>(
                      groupValue: paymentMode,
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => paymentMode = value);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            key: const ValueKey('ExpensePostCashButton'),
                            value: 'cash',
                            contentPadding: EdgeInsets.zero,
                            title: Text(isArabic ? 'نقداً' : 'Cash'),
                            subtitle: Text(isArabic
                                ? 'يمكن دفع كامل المصروف أو جزء منه'
                                : 'Pay the full expense or only part of it'),
                          ),
                          if (paymentMode == 'cash') ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              key: const ValueKey('ExpensePaidAmountField'),
                              controller: cashAmountController,
                              decoration: InputDecoration(
                                labelText: isArabic
                                    ? 'المبلغ المدفوع نقداً (USD)'
                                    : 'Amount paid in cash (USD)',
                                helperText: isArabic
                                    ? 'إجمالي المصروف: ${formatUsdReferenceAmount(expense.amount, widget.store.runtime.profile)}'
                                    : 'Expense total: ${formatUsdReferenceAmount(expense.amount, widget.store.runtime.profile)}',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}$'),
                                ),
                              ],
                              validator: (value) {
                                final amount =
                                    double.tryParse(value?.trim() ?? '');
                                if (amount == null ||
                                    !amount.isFinite ||
                                    amount <= 0) {
                                  return isArabic
                                      ? 'أدخل مبلغاً نقدياً أكبر من صفر'
                                      : 'Enter a cash amount greater than zero';
                                }
                                if (amount > expense.amount + 0.005) {
                                  return isArabic
                                      ? 'المبلغ لا يجوز أن يتجاوز إجمالي المصروف'
                                      : 'The amount cannot exceed the expense total';
                                }
                                return null;
                              },
                            ),
                          ],
                          RadioListTile<String>(
                            key: const ValueKey('ExpensePostCreditButton'),
                            value: 'credit',
                            contentPadding: EdgeInsets.zero,
                            title: Text(isArabic ? 'آجل' : 'Credit'),
                            subtitle: Text(isArabic
                                ? 'يسجل كامل المصروف كذمة مستحقة'
                                : 'Records the full expense as payable'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (paymentMode == 'cash' &&
                      !(formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  final paid = paymentMode == 'cash'
                      ? double.parse(cashAmountController.text.trim())
                      : 0.0;
                  Navigator.pop(
                    dialogContext,
                    _ExpensePostingSelection(
                      paidInCash: paymentMode == 'cash',
                      cashPaidAmount: paid,
                    ),
                  );
                },
                child: Text(isArabic ? 'ترحيل' : 'Post'),
              ),
            ],
          ),
        );
      },
    );
    cashAmountController.dispose();
    if (settlement == null) {
      return;
    }
    try {
      await widget.store.commerce.postExpense(
        expense.id,
        paidInCash: settlement.paidInCash,
        cashPaidAmount: settlement.cashPaidAmount,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('expense_posted'))),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _cancelExpense(BuildContext context, Expense expense) async {
    if (!widget.store.security.hasAnyPermission(<String>{
      AppPermission.expensesCancel,
      AppPermission.expensesManage,
    })) return;
    final tr = AppLocalizations.of(context);
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('cancel_expense')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr.text('cancel_expense_desc')),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('ExpenseCancelReasonField'),
                controller: reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: tr.text('cancel_reason_optional'))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              key: const ValueKey('ExpenseCancelConfirmButton'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('confirm'))),
        ],
      ),
    );
    if (confirmed != true) {
      reasonController.dispose();
      return;
    }
    final reason = reasonController.text.trim();
    reasonController.dispose();
    try {
      await widget.store.commerce.cancelExpense(expense.id, reason: reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('expense_cancelled'))),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _printExpense(BuildContext context, Expense expense) async {
    final tr = AppLocalizations.of(context);
    try {
      await ExpensePdfService.printExpense(
        context: context,
        expense: expense,
        profile: widget.store.runtime.profile,
        locale: Localizations.localeOf(context),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('pdf_action_failed'))),
        );
      }
    }
  }

  Future<void> _openExpenseForm(BuildContext context,
      {Expense? expense}) async {
    if (!widget.store.security.canManageExpenses) return;
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => _ExpenseDialog(
        expense: expense,
        storeProfile: widget.store.runtime.profile,
        existingExpenses: widget.store.commerce.expenses,
      ),
    );
    if (result != null) {
      try {
        if (expense?.isPosted == true) {
          await widget.store.commerce.editPostedExpense(
            expenseId: expense!.id,
            expectedVersion: expense.version,
            title: result.title,
            category: result.category,
            amount: result.amount,
            originalAmount: result.originalAmount,
            originalCurrency: result.originalCurrency,
            exchangeRateAtEntry: result.exchangeRateAtEntry,
            date: result.date,
            notes: result.notes,
          );
        } else {
          await widget.store.commerce.addOrUpdateExpense(result);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).text(expense == null
                  ? 'expense_saved_as_draft'
                  : 'expense_updated'))));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      }
    }
  }
}
