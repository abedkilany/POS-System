// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/expense.dart';
import '../../models/store_profile.dart';
import '../../models/user_role.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String query = '';
  String statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewExpenses) {
      return const _AccessDeniedScaffold(
        title: 'Expenses',
        message: 'You do not have access to expense records.',
      );
    }
    final normalizedQuery = query.trim().toLowerCase();
    final expenses = widget.store.expenses.where((expense) {
      final matchesStatus = statusFilter == 'all' ||
          (statusFilter == 'draft' && expense.isDraft) ||
          (statusFilter == 'posted' && expense.isPosted) ||
          (statusFilter == 'cancelled' && expense.isCancelled);
      if (!matchesStatus) return false;
      if (normalizedQuery.isEmpty) return true;
      return expense.title.toLowerCase().contains(normalizedQuery) ||
          expense.category.toLowerCase().contains(normalizedQuery) ||
          expense.notes.toLowerCase().contains(normalizedQuery) ||
          expense.cancelReason.toLowerCase().contains(normalizedQuery);
    }).toList();
    final filteredTotal = expenses.where((expense) => expense.isPosted).fold<double>(0, (sum, expense) => sum + expense.amount);
    final categoriesCount = widget.store.expenses.map((expense) => expense.category.trim()).where((value) => value.isNotEmpty).toSet().length;

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: tr.text('expenses'),
            subtitle: tr.text('expenses_page_desc'),
            action: FilledButton.icon(
              onPressed: widget.store.canManageExpenses
                  ? () => _openExpenseForm(context)
                  : null,
              icon: const Icon(Icons.add_card_outlined),
              label: Text(tr.text('add_expense')),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = VentioResponsive.columnsForWidth(constraints.maxWidth, mobile: 1, tablet: 3, desktop: 3);
              final gap = VentioResponsive.gap(context);
              final cardWidth = (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _MiniCard(width: cardWidth, title: tr.text('total'), value: formatUsdReferenceAmount(widget.store.totalExpensesAmount, widget.store.storeProfile), icon: Icons.payments_outlined),
                  _MiniCard(width: cardWidth, title: tr.text('expenses_count'), value: '${widget.store.expenses.length}', icon: Icons.receipt_outlined),
                  _MiniCard(width: cardWidth, title: tr.text('category'), value: '$categoriesCount', icon: Icons.category_outlined),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: tr.text('search_expense'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty ? null : IconButton(onPressed: () => setState(() => query = ''), icon: const Icon(Icons.close)),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(label: Text('${tr.text('all')} (${widget.store.expenses.length})'), selected: statusFilter == 'all', onSelected: (_) => setState(() => statusFilter = 'all')),
                const SizedBox(width: 8),
                ChoiceChip(label: Text('${tr.text('draft')} (${widget.store.expenses.where((e) => e.isDraft).length})'), selected: statusFilter == 'draft', onSelected: (_) => setState(() => statusFilter = 'draft')),
                const SizedBox(width: 8),
                ChoiceChip(label: Text('${tr.text('posted')} (${widget.store.expenses.where((e) => e.isPosted).length})'), selected: statusFilter == 'posted', onSelected: (_) => setState(() => statusFilter = 'posted')),
                const SizedBox(width: 8),
                ChoiceChip(label: Text('${tr.text('cancelled')} (${widget.store.expenses.where((e) => e.isCancelled).length})'), selected: statusFilter == 'cancelled', onSelected: (_) => setState(() => statusFilter = 'cancelled')),
              ],
            ),
          ),
          if (normalizedQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${tr.text('total')}: ${formatUsdReferenceAmount(filteredTotal, widget.store.storeProfile)}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: expenses.isEmpty
                ? EmptyStateCard(icon: Icons.payments_outlined, title: tr.text('no_expenses'), subtitle: tr.text('no_expenses_desc'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final rowExtent = constraints.maxWidth < 620 ? 188.0 : 168.0;
                      return ListView.builder(
                        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: expenses.length,
                        itemBuilder: (context, index) => _ExpenseCard(
                          expense: expenses[index],
                          storeProfile: widget.store.storeProfile,
                          onEdit: expenses[index].isDraft && widget.store.canManageExpenses ? () => _openExpenseForm(context, expense: expenses[index]) : null,
                          onPost: expenses[index].isDraft && widget.store.hasAnyPermission(<String>{AppPermission.expensesApprove, AppPermission.expensesManage}) ? () => _postExpense(context, expenses[index]) : null,
                          onCancel: expenses[index].isPosted && widget.store.hasAnyPermission(<String>{AppPermission.expensesCancel, AppPermission.expensesManage}) ? () => _cancelExpense(context, expenses[index]) : null,
                          onDeleteDraft: expenses[index].isDraft && widget.store.hasAnyPermission(<String>{AppPermission.expensesDelete, AppPermission.expensesManage}) ? () => _deleteExpense(context, expenses[index]) : null,
                          onPermanentDelete: expenses[index].isCancelled && widget.store.hasPermission(AppPermission.databaseManage) ? () => _permanentlyDeleteExpense(context, expenses[index]) : null,
                        ),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('confirm'))),
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
            TextField(controller: reasonController, maxLines: 2, decoration: InputDecoration(labelText: tr.text('cancel_reason_optional'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('confirm'))),
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

  Future<void> _permanentlyDeleteExpense(BuildContext context, Expense expense) async {
    if (!widget.store.hasPermission(AppPermission.databaseManage)) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('permanently_delete_expense')),
        content: Text(tr.text('permanently_delete_expense_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('permanently_delete'))),
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

  Future<void> _openExpenseForm(BuildContext context, {Expense? expense}) async {
    if (!widget.store.canManageExpenses) return;
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => _ExpenseDialog(expense: expense, storeProfile: widget.store.storeProfile),
    );
    if (result != null) {
      try {
        await widget.store.addOrUpdateExpense(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text(expense == null ? 'expense_saved_as_draft' : 'expense_updated'))));
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
  const _ExpenseCard({required this.expense, required this.storeProfile, this.onEdit, this.onPost, this.onCancel, this.onDeleteDraft, this.onPermanentDelete});

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
    final originalAmount = formatCurrency(expense.originalAmount ?? expense.amount, currency: expense.originalCurrency);
    final referenceAmount = formatUsdReferenceAmount(expense.amount, storeProfile);
    final statusText = expense.isCancelled ? tr.text('cancelled') : expense.isPosted ? tr.text('posted') : tr.text('draft');
    final statusIcon = expense.isCancelled ? Icons.block_outlined : expense.isPosted ? Icons.verified_outlined : Icons.edit_note_outlined;

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
                  Text(expense.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text(expense.category), visualDensity: VisualDensity.compact),
                      Chip(avatar: Icon(statusIcon, size: 16), label: Text(statusText), visualDensity: VisualDensity.compact),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (expense.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(expense.notes.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  if (expense.isCancelled && expense.cancelReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${tr.text('cancel_reason_optional')}: ${expense.cancelReason.trim()}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    expense.originalCurrency == 'USD' ? referenceAmount : '$originalAmount • $referenceAmount',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                if (onEdit != null) PopupMenuItem(value: 'edit', child: Text(tr.text('edit_expense'))),
                if (onPost != null) PopupMenuItem(value: 'post', child: Text(tr.text('post_expense'))),
                if (onCancel != null) PopupMenuItem(value: 'cancel', child: Text(tr.text('cancel_expense'))),
                if (onDeleteDraft != null) PopupMenuItem(value: 'delete', child: Text(tr.text('delete'))),
                if (onPermanentDelete != null) PopupMenuItem(value: 'permanent_delete', child: Text(tr.text('permanently_delete'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({this.expense, required this.storeProfile});

  final Expense? expense;
  final StoreProfile storeProfile;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController titleController;
  late final TextEditingController categoryController;
  late final TextEditingController amountController;
  late final TextEditingController notesController;
  String amountCurrency = 'USD';
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    titleController = TextEditingController(text: expense?.title ?? '');
    categoryController = TextEditingController(text: expense?.category ?? '');
    amountCurrency = expense?.originalCurrency ?? widget.storeProfile.defaultProductCurrency;
    amountController = TextEditingController(text: (expense?.originalAmount ?? expense?.amount)?.toString() ?? '');
    notesController = TextEditingController(text: expense?.notes ?? '');
    selectedDate = expense?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    titleController.dispose();
    categoryController.dispose();
    amountController.dispose();
    notesController.dispose();
    super.dispose();
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
      title: Text(widget.expense == null ? tr.text('add_expense') : tr.text('edit_expense')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: titleController, decoration: InputDecoration(labelText: tr.text('expense_title')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: categoryController, decoration: InputDecoration(labelText: tr.text('category')), validator: _required),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: amountController,
                        decoration: InputDecoration(labelText: tr.text('amount')),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))],
                        validator: _amountValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: amountCurrency,
                        decoration: InputDecoration(labelText: tr.text('currency')),
                        items: const [
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                        ],
                        onChanged: (value) => setState(() => amountCurrency = value ?? 'USD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: tr.text('date'), prefixIcon: const Icon(Icons.calendar_today_outlined)),
                    child: Text(DateFormat('yyyy-MM-dd HH:mm').format(selectedDate.toLocal())),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: notesController, decoration: InputDecoration(labelText: tr.text('notes')), maxLines: 3),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final originalAmount = double.parse(amountController.text.trim());
            final amount = toUsdReferencePrice(originalAmount, amountCurrency, widget.storeProfile);
            Navigator.pop(
              context,
              Expense(
                id: widget.expense?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                title: titleController.text.trim(),
                category: categoryController.text.trim(),
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
                lastModifiedByDeviceId: widget.expense?.lastModifiedByDeviceId ?? '',
              ),
            );
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
    if (!mounted) return;
    setState(() {
      selectedDate = DateTime(date.year, date.month, date.day, time?.hour ?? selectedDate.hour, time?.minute ?? selectedDate.minute);
    });
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? AppLocalizations.of(context).text('required') : null;

  String? _amountValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return AppLocalizations.of(context).text('required');
    final number = double.tryParse(trimmed);
    if (number == null || number <= 0) return AppLocalizations.of(context).text('invalid_number');
    return null;
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.width, required this.title, required this.value, required this.icon});

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
