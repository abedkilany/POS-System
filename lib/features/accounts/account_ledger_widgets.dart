import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';

String accountBalanceText(BuildContext context, AppStore store, String accountType, String accountId) {
  final tr = AppLocalizations.of(context);
  final balance = store.accountBalance(accountType, accountId);
  if (balance.abs() < 0.0001) return tr.text('account_settled');
  final amount = formatUsdReferenceAmount(balance.abs(), store.storeProfile);
  if (accountType == 'customer') return balance > 0 ? '${tr.text('account_receivable')}: $amount' : '${tr.text('account_credit')}: $amount';
  return balance > 0 ? '${tr.text('account_advance')}: $amount' : '${tr.text('account_payable')}: $amount';
}

Color accountBalanceColor(BuildContext context, AppStore store, String accountType, String accountId) {
  final balance = store.accountBalance(accountType, accountId);
  if (balance.abs() < 0.0001) return Theme.of(context).colorScheme.primary;
  if (accountType == 'customer') return balance > 0 ? Colors.orange.shade700 : Colors.green.shade700;
  return balance < 0 ? Colors.orange.shade700 : Colors.green.shade700;
}

Future<void> showAccountLedgerSheet({
  required BuildContext context,
  required AppStore store,
  required String accountType,
  required String accountId,
  required String accountName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountLedgerSheet(store: store, accountType: accountType, accountId: accountId, accountName: accountName),
  );
}

Future<void> showAccountPaymentDialog({
  required BuildContext context,
  required AppStore store,
  required String accountType,
  required String accountId,
  required String accountName,
}) async {
  final result = await showDialog<_PaymentDraft>(
    context: context,
    builder: (_) => _PaymentDialog(accountType: accountType, accountName: accountName),
  );
  if (result == null) return;
  final now = DateTime.now();
  final isCustomer = accountType == 'customer';
  await store.addOrUpdateAccountTransaction(AccountTransaction(
    id: 'txn-${now.microsecondsSinceEpoch}',
    accountType: accountType,
    accountId: accountId,
    accountName: accountName,
    date: now,
    type: isCustomer ? 'paymentReceived' : 'paymentPaid',
    referenceId: '',
    referenceNo: result.referenceNo,
    paymentMethod: result.paymentMethod,
    debit: isCustomer ? 0 : result.amount,
    credit: isCustomer ? result.amount : 0,
    note: result.note,
  ));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('payment_saved'))));
  }
}

class _AccountLedgerSheet extends StatelessWidget {
  const _AccountLedgerSheet({required this.store, required this.accountType, required this.accountId, required this.accountName});

  final AppStore store;
  final String accountType, accountId, accountName;

  @override
  Widget build(BuildContext context) {
    final rows = store.accountTransactionsForAccount(accountType, accountId);
    final balance = store.accountBalance(accountType, accountId);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(accountName, style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(AppLocalizations.of(context).text('current_balance')),
                subtitle: Text(_balanceDescription(context, accountType, balance)),
                trailing: Text(formatUsdReferenceAmount(balance.abs(), store.storeProfile), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(AppLocalizations.of(context).text('no_account_transactions')))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _TransactionTile(store: store, transaction: rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _balanceDescription(BuildContext context, String type, double balance) {
    final tr = AppLocalizations.of(context);
    if (balance.abs() < 0.0001) return tr.text('account_settled_description');
    if (type == 'customer') return balance > 0 ? tr.text('amount_to_collect_from_customer') : tr.text('customer_credit_balance');
    return balance < 0 ? tr.text('amount_to_pay_supplier') : tr.text('supplier_advance_balance');
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.store, required this.transaction});

  final AppStore store;
  final AccountTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final amount = transaction.debit > 0 ? transaction.debit : transaction.credit;
    final sign = transaction.debit > 0 ? '+' : '-';
    return ListTile(
      dense: true,
      leading: Icon(_iconForType(transaction.type)),
      title: Text(_titleForType(context, transaction.type)),
      subtitle: Text([
        _dateText(transaction.date),
        transaction.referenceNo,
        transaction.note,
      ].where((part) => part.trim().isNotEmpty).join(' • ')),
      trailing: Text('$sign ${formatUsdReferenceAmount(amount, store.storeProfile)}'),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'saleInvoice':
        return Icons.receipt_long_outlined;
      case 'purchaseInvoice':
        return Icons.inventory_2_outlined;
      case 'paymentReceived':
        return Icons.payments_outlined;
      case 'paymentPaid':
        return Icons.payment_outlined;
      case 'cancel':
      case 'paymentReversal':
        return Icons.undo_outlined;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  String _titleForType(BuildContext context, String type) {
    final tr = AppLocalizations.of(context);
    switch (type) {
      case 'saleInvoice':
        return tr.text('sale_invoice');
      case 'purchaseInvoice':
        return tr.text('purchase_invoice');
      case 'paymentReceived':
        return tr.text('payment_received');
      case 'paymentPaid':
        return tr.text('payment_paid');
      case 'paymentReversal':
        return tr.text('payment_reversal');
      case 'cancel':
        return tr.text('cancellation_reversal');
      case 'adjustment':
        return tr.text('adjustment');
      default:
        return type;
    }
  }

  String _dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _PaymentDraft {
  const _PaymentDraft({required this.amount, required this.note, required this.referenceNo, required this.paymentMethod});
  final double amount;
  final String note;
  final String referenceNo;
  final String paymentMethod;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.accountType, required this.accountName});
  final String accountType, accountName;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  final noteController = TextEditingController();
  String paymentMethod = 'Cash';

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isCustomer = widget.accountType == 'customer';
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 600);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(isCustomer ? tr.text('receive_payment') : tr.text('pay_supplier')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(alignment: AlignmentDirectional.centerStart, child: Text(widget.accountName, style: Theme.of(context).textTheme.titleMedium)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr.text('amount')),
                  validator: (value) {
                    final amount = double.tryParse((value ?? '').trim());
                    if (amount == null || amount <= 0) return tr.text('enter_valid_amount');
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: InputDecoration(labelText: tr.text('payment_method')),
                  items: [
                    DropdownMenuItem(value: 'Cash', child: Text(tr.text('payment_cash'))),
                    DropdownMenuItem(value: 'Card', child: Text(tr.text('payment_card'))),
                    DropdownMenuItem(value: 'Wish', child: Text(tr.text('payment_wish'))),
                    DropdownMenuItem(value: 'Check', child: Text(tr.text('payment_check'))),
                  ],
                  onChanged: (value) => setState(() => paymentMethod = value ?? 'Cash'),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: referenceController, decoration: InputDecoration(labelText: tr.text('reference_no_optional'))),
                const SizedBox(height: 12),
                TextFormField(controller: noteController, decoration: InputDecoration(labelText: tr.text('notes')), maxLines: 3),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, _PaymentDraft(amount: double.parse(amountController.text.trim()), referenceNo: referenceController.text.trim(), note: noteController.text.trim(), paymentMethod: paymentMethod));
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }
}
