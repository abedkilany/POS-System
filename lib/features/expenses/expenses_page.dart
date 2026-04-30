import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/expense.dart';
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

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final expenses = widget.store.expenses.where((expense) {
      final value = query.toLowerCase();
      return expense.title.toLowerCase().contains(value) || expense.category.toLowerCase().contains(value);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('expenses'),
            subtitle: tr.text('expenses_page_desc'),
            action: FilledButton.icon(
              onPressed: () => _openExpenseForm(context),
              icon: const Icon(Icons.add_card_outlined),
              label: Text(tr.text('add_expense')),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _MiniCard(title: tr.text('expenses'), value: formatCurrency(widget.store.totalExpensesAmount, currency: widget.store.storeProfile.currency), icon: Icons.payments_outlined),
              _MiniCard(title: tr.text('expenses_count'), value: '${widget.store.expenses.length}', icon: Icons.receipt_outlined),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(hintText: tr.text('search_expense'), prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: expenses.isEmpty
                ? EmptyStateCard(icon: Icons.payments_outlined, title: tr.text('no_expenses'), subtitle: tr.text('no_expenses_desc'))
                : Card(
                    child: ListView.separated(
                      itemCount: expenses.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final expense = expenses[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
                          title: Text(expense.title),
                          subtitle: Text('${expense.category} • ${expense.date.toLocal()}'.split('.').first),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(formatCurrency(expense.amount, currency: widget.store.storeProfile.currency)),
                              IconButton(onPressed: () => _openExpenseForm(context, expense: expense), icon: const Icon(Icons.edit_outlined)),
                              IconButton(onPressed: () => _deleteExpense(context, expense), icon: const Icon(Icons.delete_outline)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(BuildContext context, Expense expense) async {
    await widget.store.deleteExpense(expense.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Expense deleted: ${expense.title}')));
    }
  }

  Future<void> _openExpenseForm(BuildContext context, {Expense? expense}) async {
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => _ExpenseDialog(expense: expense),
    );
    if (result != null) {
      await widget.store.addOrUpdateExpense(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(expense == null ? 'Expense saved' : 'Expense updated')));
      }
    }
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({this.expense});

  final Expense? expense;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController titleController;
  late final TextEditingController categoryController;
  late final TextEditingController amountController;
  late final TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    titleController = TextEditingController(text: expense?.title ?? '');
    categoryController = TextEditingController(text: expense?.category ?? '');
    amountController = TextEditingController(text: expense?.amount.toString() ?? '');
    notesController = TextEditingController(text: expense?.notes ?? '');
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
    return AlertDialog(
      title: Text(widget.expense == null ? tr.text('add_expense') : tr.text('edit_expense')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: titleController, decoration: InputDecoration(labelText: tr.text('expense_title')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: categoryController, decoration: InputDecoration(labelText: tr.text('category')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: amountController, decoration: InputDecoration(labelText: tr.text('amount')), keyboardType: TextInputType.number, validator: _required),
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
            Navigator.pop(
              context,
              Expense(
                id: widget.expense?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                title: titleController.text.trim(),
                category: categoryController.text.trim(),
                amount: double.tryParse(amountController.text.trim()) ?? 0,
                date: widget.expense?.date ?? DateTime.now(),
                notes: notesController.text.trim(),
              ),
            );
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
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
