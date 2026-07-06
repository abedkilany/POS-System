// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/revision_cache.dart';
import '../../data/app_store.dart';
import '../../models/expense.dart';
import '../../models/store_profile.dart';
import '../../models/user_role.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/page_data_load_indicator.dart';

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
    if (!widget.store.canViewExpenses) {
      return const _AccessDeniedScaffold(
        title: 'Expenses',
        message: 'You do not have access to expense records.',
      );
    }
    if (!widget.store.isCoreDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final normalizedQuery = query.trim().toLowerCase();
    final overview = widget.store.expensesOverview;
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
    final allExpenses = widget.store.expenses;
    final useDefaultView = statusFilter == 'all' && normalizedQuery.isEmpty;
    final expenses = useDefaultView
        ? allExpenses
        : _filteredExpensesCache.getOrCompute(
            widget.store.expensesRevision,
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
            widget.store.expensesRevision,
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
        '${widget.store.expensesRevision}|$statusFilter|$normalizedQuery|$limit';
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
            ? widget.store.expensesOverview.totalExpensesAmount
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
                FilledButton.icon(
                  onPressed: widget.store.canManageExpenses
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
                          widget.store.storeProfile),
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
                '${tr.text('total')}: ${formatUsdReferenceAmount(filteredTotal, widget.store.storeProfile)}',
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
                                storeProfile: widget.store.storeProfile,
                                onEdit: expense.isDraft &&
                                        widget.store.canManageExpenses
                                    ? () => _openExpenseForm(context,
                                        expense: expense)
                                    : null,
                                onPost: expense.isDraft &&
                                        widget.store.hasAnyPermission(<String>{
                                          AppPermission.expensesApprove,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _postExpense(context, expense)
                                    : null,
                                onCancel: expense.isPosted &&
                                        widget.store.hasAnyPermission(<String>{
                                          AppPermission.expensesCancel,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _cancelExpense(context, expense)
                                    : null,
                                onDeleteDraft: expense.isDraft &&
                                        widget.store.hasAnyPermission(<String>{
                                          AppPermission.expensesDelete,
                                          AppPermission.expensesManage
                                        })
                                    ? () => _deleteExpense(context, expense)
                                    : null,
                                onPermanentDelete: expense.isCancelled &&
                                        widget.store.hasPermission(
                                            AppPermission.databaseManage)
                                    ? () => _permanentlyDeleteExpense(
                                        context, expense)
                                    : null,
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
    if (!widget.store.hasAnyPermission(<String>{
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
      await widget.store.deleteDraftExpense(expense.id);
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
    if (!widget.store.hasAnyPermission(<String>{
      AppPermission.expensesApprove,
      AppPermission.expensesManage,
    })) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('post_expense')),
        content: Text(tr.text('post_expense_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('confirm'))),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.postExpense(expense.id);
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
    if (!widget.store.hasAnyPermission(<String>{
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
      await widget.store.cancelExpense(expense.id, reason: reason);
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

  Future<void> _permanentlyDeleteExpense(
      BuildContext context, Expense expense) async {
    if (!widget.store.hasPermission(AppPermission.databaseManage)) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('permanently_delete_expense')),
        content: Text(tr.text('permanently_delete_expense_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('permanently_delete'))),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.permanentlyDeleteCancelledExpense(expense.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('expense_permanently_deleted'))),
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

  Future<void> _openExpenseForm(BuildContext context,
      {Expense? expense}) async {
    if (!widget.store.canManageExpenses) return;
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => _ExpenseDialog(
        expense: expense,
        storeProfile: widget.store.storeProfile,
        existingExpenses: widget.store.expenses,
      ),
    );
    if (result != null) {
      try {
        await widget.store.addOrUpdateExpense(result);
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

class _ExpenseQueryResult {
  const _ExpenseQueryResult({
    required this.items,
    required this.totalCount,
    required this.filteredPostedTotal,
  });

  final List<Expense> items;
  final int totalCount;
  final double filteredPostedTotal;

  bool get hasMore => items.length < totalCount;
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard(
      {required this.expense,
      required this.storeProfile,
      this.onEdit,
      this.onPost,
      this.onCancel,
      this.onDeleteDraft,
      this.onPermanentDelete});

  final Expense expense;
  final StoreProfile storeProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onPost;
  final VoidCallback? onCancel;
  final VoidCallback? onDeleteDraft;
  final VoidCallback? onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final date = DateFormat('yyyy-MM-dd HH:mm').format(expense.date.toLocal());
    final originalAmount = formatCurrency(
        expense.originalAmount ?? expense.amount,
        currency: expense.originalCurrency);
    final referenceAmount =
        formatUsdReferenceAmount(expense.amount, storeProfile);
    final statusText = expense.isCancelled
        ? tr.text('cancelled')
        : expense.isPosted
            ? tr.text('posted')
            : tr.text('draft');
    final statusIcon = expense.isCancelled
        ? Icons.block_outlined
        : expense.isPosted
            ? Icons.verified_outlined
            : Icons.edit_note_outlined;

    return Card(
      child: Padding(
        padding: VentioResponsive.cardInsets(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.payments_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                          label: Text(expense.category),
                          visualDensity: VisualDensity.compact),
                      Chip(
                          avatar: Icon(statusIcon, size: 16),
                          label: Text(statusText),
                          visualDensity: VisualDensity.compact),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (expense.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(expense.notes.trim(),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  if (expense.isCancelled &&
                      expense.cancelReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                        '${tr.text('cancel_reason_optional')}: ${expense.cancelReason.trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    expense.originalCurrency == 'USD'
                        ? referenceAmount
                        : '$originalAmount • $referenceAmount',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'post':
                    onPost?.call();
                    break;
                  case 'cancel':
                    onCancel?.call();
                    break;
                  case 'delete':
                    onDeleteDraft?.call();
                    break;
                  case 'permanent_delete':
                    onPermanentDelete?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  PopupMenuItem(
                      value: 'edit', child: Text(tr.text('edit_expense'))),
                if (onPost != null)
                  PopupMenuItem(
                      value: 'post', child: Text(tr.text('post_expense'))),
                if (onCancel != null)
                  PopupMenuItem(
                      value: 'cancel', child: Text(tr.text('cancel_expense'))),
                if (onDeleteDraft != null)
                  PopupMenuItem(
                      value: 'delete', child: Text(tr.text('delete'))),
                if (onPermanentDelete != null)
                  PopupMenuItem(
                      value: 'permanent_delete',
                      child: Text(tr.text('permanently_delete'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCatalogItem {
  const _ExpenseCatalogItem(
      {required this.en, required this.ar, this.archived = false});

  final String en;
  final String ar;
  final bool archived;

  String label(BuildContext context) {
    final isArabic = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('ar');
    if (ar.trim().isEmpty) return en;
    return isArabic ? '$ar / $en' : '$en / $ar';
  }

  _ExpenseCatalogItem copyWith({String? en, String? ar, bool? archived}) =>
      _ExpenseCatalogItem(
          en: en ?? this.en,
          ar: ar ?? this.ar,
          archived: archived ?? this.archived);

  Map<String, dynamic> toJson() => {'en': en, 'ar': ar, 'archived': archived};

  factory _ExpenseCatalogItem.fromJson(Map<String, dynamic> json) =>
      _ExpenseCatalogItem(
        en: (json['en'] ?? '').toString().trim(),
        ar: (json['ar'] ?? '').toString().trim(),
        archived: json['archived'] == true,
      );
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    this.expense,
    required this.storeProfile,
    required this.existingExpenses,
  });

  final Expense? expense;
  final StoreProfile storeProfile;
  final List<Expense> existingExpenses;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

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
