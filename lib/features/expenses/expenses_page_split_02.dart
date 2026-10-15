// ignore_for_file: curly_braces_in_flow_control_structures
part of 'expenses_page.dart';

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

class _ExpensePostingSelection {
  const _ExpensePostingSelection({
    required this.paidInCash,
    required this.cashPaidAmount,
  });

  final bool paidInCash;
  final double cashPaidAmount;
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
      this.onPrint,
      this.onPost,
      this.onCancel,
      this.onDeleteDraft,
      this.onPermanentDelete});

  final Expense expense;
  final StoreProfile storeProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
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
            IconButton(
              tooltip: tr.text('print_expense'),
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'print':
                    onPrint?.call();
                    break;
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
                if (onPrint != null)
                  PopupMenuItem(
                      value: 'print', child: Text(tr.text('print_expense'))),
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
