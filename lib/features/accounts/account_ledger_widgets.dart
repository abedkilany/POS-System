import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/cash_receipt_pdf_service.dart';
import '../../core/services/payment_voucher_service.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import 'account_statement_actions.dart';
import '../../models/account_transaction.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/payment_allocation.dart';
import '../../models/sale.dart';

String accountBalanceText(BuildContext context, AppStore store,
    String accountType, String accountId) {
  final tr = AppLocalizations.of(context);
  final balance = store.accountBalance(accountType, accountId);
  if (balance.abs() < 0.0001) return tr.text('account_settled');
  final amount = formatUsdReferenceAmount(balance.abs(), store.storeProfile);
  if (accountType == 'customer') {
    return balance > 0
        ? '${tr.text('account_receivable')}: $amount'
        : '${tr.text('account_credit')}: $amount';
  }
  return balance > 0
      ? '${tr.text('account_advance')}: $amount'
      : '${tr.text('account_payable')}: $amount';
}

Color accountBalanceColor(BuildContext context, AppStore store,
    String accountType, String accountId) {
  final balance = store.accountBalance(accountType, accountId);
  if (balance.abs() < 0.0001) return Theme.of(context).colorScheme.primary;
  if (accountType == 'customer') {
    return balance > 0 ? Colors.orange.shade700 : Colors.green.shade700;
  }
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
    builder: (_) => _AccountLedgerSheet(
        store: store,
        accountType: accountType,
        accountId: accountId,
        accountName: accountName),
  );
}

Future<void> showAccountPaymentDialog({
  required BuildContext context,
  required AppStore store,
  required String accountType,
  required String accountId,
  required String accountName,
}) async {
  final normalizedAccountId = accountId.trim();
  final customerInvoices = accountType == 'customer'
      ? store.sales
          .where((sale) =>
              !sale.isCancelled &&
              sale.balanceDue > 0.000001 &&
              sale.customerId.trim() == normalizedAccountId)
          .toList()
      : <Sale>[];
  customerInvoices.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.invoiceNo.compareTo(b.invoiceNo);
  });

  final result = await showDialog<_PaymentDraft>(
    context: context,
    builder: (_) => _PaymentDialog(
      store: store,
      accountType: accountType,
      accountName: accountName,
      customerInvoices: customerInvoices,
    ),
  );
  if (result == null) return;
  if (accountType == 'supplier' &&
      result.referenceNo.trim().isEmpty &&
      result.note.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).text('payment_reference_required'),
          ),
        ),
      );
    }
    return;
  }
  try {
    await store.settleAccountPayment(
      accountType: accountType,
      accountId: accountId,
      accountName: accountName,
      amount: result.amount,
      paymentMethod: result.paymentMethod,
      referenceNo: result.referenceNo,
      notes: result.note,
      allocations: result.allocations,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).text('payment_saved'))));
  } catch (error) {
    if (!context.mounted) return;
    final tr = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
    );
  }
}

class _AccountLedgerSheet extends StatelessWidget {
  const _AccountLedgerSheet(
      {required this.store,
      required this.accountType,
      required this.accountId,
      required this.accountName});

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
                Expanded(
                    child: Text(accountName,
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                    tooltip: AppLocalizations.of(context)
                        .text('print_account_statement'),
                    onPressed: () => printAccountStatementForAccount(
                          context: context,
                          store: store,
                          accountType: accountType,
                          accountId: accountId,
                          accountName: accountName,
                        ),
                    icon: const Icon(Icons.print_outlined)),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title:
                    Text(AppLocalizations.of(context).text('current_balance')),
                subtitle:
                    Text(_balanceDescription(context, accountType, balance)),
                trailing: Text(
                    formatUsdReferenceAmount(balance.abs(), store.storeProfile),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(AppLocalizations.of(context)
                          .text('no_account_transactions')))
                  : ListView.builder(
                      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      controller: scrollController,
                      itemExtent: 72.0,
                      itemCount: rows.length,
                      itemBuilder: (context, index) => _TransactionTile(
                          store: store, transaction: rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _balanceDescription(
      BuildContext context, String type, double balance) {
    final tr = AppLocalizations.of(context);
    if (balance.abs() < 0.0001) return tr.text('account_settled_description');
    if (type == 'customer') {
      return balance > 0
          ? tr.text('amount_to_collect_from_customer')
          : tr.text('customer_credit_balance');
    }
    return balance < 0
        ? tr.text('amount_to_pay_supplier')
        : tr.text('supplier_advance_balance');
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.store, required this.transaction});

  final AppStore store;
  final AccountTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.debit > 0;
    final amount = isDebit ? transaction.debit : transaction.credit;
    final postingLabel =
        AppLocalizations.of(context).text(isDebit ? 'debit' : 'credit');
    return ListTile(
      dense: true,
      leading: Icon(_iconForType(transaction.type)),
      title: Text(_titleForType(context, transaction.type)),
      subtitle: Text([
        _dateText(transaction.date),
        transaction.referenceNo,
        transaction.note,
      ].where((part) => part.trim().isNotEmpty).join(' • ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                postingLabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(formatUsdReferenceAmount(amount, store.storeProfile)),
            ],
          ),
          if (_isReceiptMovement(transaction)) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'طباعة الإيصال'
                  : 'Print receipt',
              onPressed: () => _printReceipt(context),
              icon: const Icon(Icons.print_outlined, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  bool _isReceiptMovement(AccountTransaction item) =>
      item.type == 'paymentReceived' || item.type == 'paymentPaid';

  Future<void> _printReceipt(BuildContext context) async {
    try {
      final printable = await _resolvePrintableReceipt();
      if (!context.mounted) return;
      await CashReceiptPdfService.printReceipt(
        transaction: printable,
        profile: store.storeProfile,
        locale: Localizations.localeOf(context),
      );
    } catch (error) {
      if (!context.mounted) return;
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تعذر طباعة الإيصال: $error'
                : 'Could not print receipt: $error',
          ),
        ),
      );
    }
  }

  String? _voucherIdFromCompatibilityMovement() {
    final suffixes = transaction.type == 'paymentReceived'
        ? const <String>['-customer-payment', '-customer-account-payment']
        : const <String>['-supplier-payment', '-supplier-account-payment'];
    for (final suffix in suffixes) {
      final index = transaction.id.indexOf(suffix);
      if (index <= 0) continue;
      final trailing = transaction.id.substring(index + suffix.length);
      if (trailing.isEmpty || trailing.startsWith('-')) {
        return transaction.id.substring(0, index);
      }
    }
    return null;
  }

  Future<CashLedgerTransaction> _resolvePrintableReceipt() async {
    final db = SqliteMigrationManager.database;
    if (db != null) {
      final ledger = CashLedgerService(db);
      CashLedgerTransaction? found;

      final voucherId = _voucherIdFromCompatibilityMovement();
      if (voucherId != null) {
        final rows = await ledger.list(
          referenceType: transaction.type == 'paymentReceived'
              ? 'receipt_voucher'
              : 'payment_voucher',
          referenceId: voucherId,
          limit: 1,
        );
        if (rows.isNotEmpty) found = rows.first;
      }

      if (found == null) {
        final rows = await ledger.list(
          referenceType: 'legacy_account_transaction',
          referenceId: transaction.id,
          limit: 1,
        );
        if (rows.isNotEmpty) found = rows.first;
      }

      if (found == null) {
        await PaymentVoucherService(db).backfillLegacyCashLedger();

        final voucherId = _voucherIdFromCompatibilityMovement();
        if (voucherId != null) {
          final rows = await ledger.list(
            referenceType: transaction.type == 'paymentReceived'
                ? 'receipt_voucher'
                : 'payment_voucher',
            referenceId: voucherId,
            limit: 1,
          );
          if (rows.isNotEmpty) found = rows.first;
        }

        if (found == null) {
          final rows = await ledger.list(
            referenceType: 'legacy_account_transaction',
            referenceId: transaction.id,
            limit: 1,
          );
          if (rows.isNotEmpty) found = rows.first;
        }
      }

      if (found != null) return found;
    }

    final amount =
        transaction.debit > 0 ? transaction.debit : transaction.credit;
    final isReceipt = transaction.type == 'paymentReceived';
    return CashLedgerTransaction(
      id: transaction.id,
      type: isReceipt ? 'receipt' : 'supplier_payment',
      direction: isReceipt ? 'in' : 'out',
      amount: amount,
      currency: transaction.currency,
      cashLocationId: '',
      referenceType: 'account_transaction',
      referenceId: transaction.referenceId,
      referenceNumber: transaction.referenceNo,
      partyType: transaction.accountType,
      partyId: transaction.accountId,
      partyName: transaction.accountName,
      paymentMethod: transaction.paymentMethod.trim().isEmpty
          ? 'Cash'
          : transaction.paymentMethod,
      deviceId: transaction.deviceId,
      branchId: transaction.branchId,
      storeId: transaction.storeId,
      notes: transaction.note,
      occurredAt: transaction.date.toUtc(),
      createdAt: transaction.createdAt.toUtc(),
      updatedAt: transaction.updatedAt.toUtc(),
      lastModifiedByDeviceId: transaction.lastModifiedByDeviceId,
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

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _PaymentDraft {
  const _PaymentDraft({
    required this.amount,
    required this.note,
    required this.referenceNo,
    required this.paymentMethod,
    required this.allocations,
  });

  final double amount;
  final String note;
  final String referenceNo;
  final String paymentMethod;
  final List<PaymentAllocationDraft> allocations;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.store,
    required this.accountType,
    required this.accountName,
    required this.customerInvoices,
  });

  final AppStore store;
  final String accountType, accountName;
  final List<Sale> customerInvoices;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  final noteController = TextEditingController();
  final Set<String> selectedInvoiceIds = <String>{};
  String paymentMethod = 'Cash';
  late String allocationMode;
  String submitError = '';

  bool get _isCustomer => widget.accountType == 'customer';
  bool get _hasOpenInvoices =>
      _isCustomer && widget.customerInvoices.isNotEmpty;
  String get _voucherCurrency =>
      widget.store.storeProfile.baseCurrency.toUpperCase();

  @override
  void initState() {
    super.initState();
    allocationMode = _hasOpenInvoices ? 'invoices' : 'account';
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    noteController.dispose();
    super.dispose();
  }

  double? _invoiceDueInVoucherCurrency(Sale sale) {
    try {
      return convertCurrency(
        sale.balanceDue,
        sale.invoiceCurrency,
        _voucherCurrency,
        widget.store.storeProfile,
        effectiveAt: DateTime.now(),
        normalizeResult: false,
      );
    } catch (_) {
      return null;
    }
  }

  List<Sale> get _selectedInvoices => widget.customerInvoices
      .where((sale) => selectedInvoiceIds.contains(sale.id))
      .toList(growable: false);

  double get _selectedTotal {
    var total = 0.0;
    for (final sale in _selectedInvoices) {
      final due = _invoiceDueInVoucherCurrency(sale);
      if (due != null) total += due;
    }
    return normalizeAccountingAmount(
      total,
      _voucherCurrency,
      widget.store.storeProfile,
    );
  }

  String _amountText(double value) {
    final decimals = accountingDecimalsForCurrency(
      _voucherCurrency,
      widget.store.storeProfile,
    );
    return normalizeAccountingAmount(
      value,
      _voucherCurrency,
      widget.store.storeProfile,
    ).toStringAsFixed(decimals);
  }

  void _syncAmountToSelection() {
    amountController.text = _amountText(_selectedTotal);
  }

  void _toggleInvoice(Sale sale, bool selected) {
    if (_invoiceDueInVoucherCurrency(sale) == null) return;
    setState(() {
      submitError = '';
      if (selected) {
        selectedInvoiceIds.add(sale.id);
      } else {
        selectedInvoiceIds.remove(sale.id);
      }
      _syncAmountToSelection();
    });
  }

  void _selectAllInvoices() {
    setState(() {
      submitError = '';
      selectedInvoiceIds
        ..clear()
        ..addAll(widget.customerInvoices
            .where((sale) => _invoiceDueInVoucherCurrency(sale) != null)
            .map((sale) => sale.id));
      _syncAmountToSelection();
    });
  }

  void _selectOldestFirst() {
    final requested = double.tryParse(amountController.text.trim()) ?? 0;
    final chosen = <String>{};
    var covered = 0.0;
    for (final sale in widget.customerInvoices) {
      final due = _invoiceDueInVoucherCurrency(sale);
      if (due == null) continue;
      chosen.add(sale.id);
      covered += due;
      if (requested <= 0 || covered + 0.000001 >= requested) break;
    }
    setState(() {
      submitError = '';
      selectedInvoiceIds
        ..clear()
        ..addAll(chosen);
      if (requested <= 0) _syncAmountToSelection();
    });
  }

  List<PaymentAllocationDraft> _buildAllocations(double amount) {
    if (!_isCustomer || allocationMode != 'invoices') {
      return const <PaymentAllocationDraft>[];
    }
    var remaining = normalizeAccountingAmount(
      amount,
      _voucherCurrency,
      widget.store.storeProfile,
    );
    final drafts = <PaymentAllocationDraft>[];
    for (final sale in _selectedInvoices) {
      if (remaining <= 0.000001) break;
      final dueInVoucher = _invoiceDueInVoucherCurrency(sale);
      if (dueInVoucher == null) {
        throw StateError('Missing exchange rate for ${sale.invoiceCurrency}.');
      }
      final take = remaining < dueInVoucher ? remaining : dueInVoucher;
      if (take <= 0.000001) continue;
      var referenceAmount =
          sale.invoiceCurrency.toUpperCase() == _voucherCurrency
              ? take
              : convertCurrency(
                  take,
                  _voucherCurrency,
                  sale.invoiceCurrency,
                  widget.store.storeProfile,
                  effectiveAt: DateTime.now(),
                );
      if (referenceAmount > sale.balanceDue) {
        referenceAmount = sale.balanceDue;
      }
      final exchange = take <= 0 ? 1.0 : referenceAmount / take;
      drafts.add(
        PaymentAllocationDraft(
          referenceId: sale.id,
          referenceNumber: sale.invoiceNo,
          amount: take,
          referenceAmount: referenceAmount,
          referenceCurrency: sale.invoiceCurrency,
          exchangeRate: exchange,
        ),
      );
      remaining = normalizeAccountingAmount(
        remaining - take,
        _voucherCurrency,
        widget.store.storeProfile,
      );
    }
    if (remaining > 0.000001) {
      throw StateError('Payment amount exceeds selected invoice balances.');
    }
    return drafts;
  }

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 720);
    final selectedTotal = _selectedTotal;
    final enteredAmount = double.tryParse(amountController.text.trim()) ?? 0;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(
          _isCustomer ? tr.text('receive_payment') : tr.text('pay_supplier')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.accountName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_isCustomer) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(tr.text('allocate_to_invoices')),
                          selected: allocationMode == 'invoices',
                          onSelected: _hasOpenInvoices
                              ? (_) => setState(() {
                                    allocationMode = 'invoices';
                                    submitError = '';
                                  })
                              : null,
                        ),
                        ChoiceChip(
                          label: Text(tr.text('payment_on_account')),
                          selected: allocationMode == 'account',
                          onSelected: (_) => setState(() {
                            allocationMode = 'account';
                            selectedInvoiceIds.clear();
                            submitError = '';
                          }),
                        ),
                      ],
                    ),
                    if (!_hasOpenInvoices) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr.text('no_open_customer_invoices'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (allocationMode == 'invoices' && _hasOpenInvoices) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr.text('open_customer_invoices'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _selectOldestFirst,
                            child: Text(tr.text('oldest_first')),
                          ),
                          TextButton(
                            onPressed: _selectAllInvoices,
                            child: Text(tr.text('select_all')),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 270),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: widget.customerInvoices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sale = widget.customerInvoices[index];
                            final dueInVoucher =
                                _invoiceDueInVoucherCurrency(sale);
                            final canAllocate = dueInVoucher != null;
                            final invoiceDue = formatCurrency(
                              sale.balanceDue,
                              currency: sale.invoiceCurrency,
                              profile: widget.store.storeProfile,
                            );
                            final convertedDue = canAllocate &&
                                    sale.invoiceCurrency.toUpperCase() !=
                                        _voucherCurrency
                                ? ' • ${formatCurrency(dueInVoucher, currency: _voucherCurrency, profile: widget.store.storeProfile)}'
                                : '';
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selectedInvoiceIds.contains(sale.id),
                              enabled: canAllocate,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: canAllocate
                                  ? (value) =>
                                      _toggleInvoice(sale, value ?? false)
                                  : null,
                              title: Text(
                                '${sale.invoiceNo} • ${_dateText(sale.date)}',
                              ),
                              subtitle: Text(
                                canAllocate
                                    ? '${tr.text('remaining_debt')}: $invoiceDue$convertedDue'
                                    : '${tr.text('remaining_debt')}: $invoiceDue • ${tr.text('missing_exchange_rate_for_allocation')}',
                              ),
                            );
                          },
                        ),
                      ),
                      if (selectedInvoiceIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '${tr.text('selected_invoices')}: ${selectedInvoiceIds.length} • '
                              '${tr.text('selected_balance')}: ${formatCurrency(selectedTotal, currency: _voucherCurrency, profile: widget.store.storeProfile)}',
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (allocationMode == 'account') ...[
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(tr.text('unallocated_payment_warning')),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${tr.text('amount')} ($_voucherCurrency)',
                    ),
                    onChanged: (_) {
                      if (submitError.isNotEmpty) {
                        setState(() => submitError = '');
                      } else if (allocationMode == 'invoices') {
                        setState(() {});
                      }
                    },
                    validator: (value) {
                      final amount = double.tryParse((value ?? '').trim());
                      if (amount == null || amount <= 0) {
                        return tr.text('enter_valid_amount');
                      }
                      if (_isCustomer && allocationMode == 'invoices') {
                        if (selectedInvoiceIds.isEmpty) {
                          return tr.text('select_invoice_or_on_account');
                        }
                        if (amount - selectedTotal > 0.000001) {
                          return tr.text('payment_exceeds_selected_invoices');
                        }
                      }
                      return null;
                    },
                  ),
                  if (_isCustomer &&
                      allocationMode == 'invoices' &&
                      selectedInvoiceIds.isNotEmpty &&
                      enteredAmount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${tr.text('payment_allocation_summary')}: '
                      '${formatCurrency(enteredAmount > selectedTotal ? selectedTotal : enteredAmount, currency: _voucherCurrency, profile: widget.store.storeProfile)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration:
                        InputDecoration(labelText: tr.text('payment_method')),
                    items: [
                      DropdownMenuItem(
                          value: 'Cash', child: Text(tr.text('payment_cash'))),
                      DropdownMenuItem(
                          value: 'Card', child: Text(tr.text('payment_card'))),
                      DropdownMenuItem(
                          value: 'Wish', child: Text(tr.text('payment_wish'))),
                      DropdownMenuItem(
                          value: 'Check',
                          child: Text(tr.text('payment_check'))),
                    ],
                    onChanged: (value) =>
                        setState(() => paymentMethod = value ?? 'Cash'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: referenceController,
                    decoration: InputDecoration(
                        labelText: tr.text('reference_no_optional')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: InputDecoration(labelText: tr.text('notes')),
                    maxLines: 3,
                  ),
                  if (submitError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      submitError,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr.text('cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final amount = double.parse(amountController.text.trim());
            try {
              final allocations = _buildAllocations(amount);
              Navigator.pop(
                context,
                _PaymentDraft(
                  amount: amount,
                  referenceNo: referenceController.text.trim(),
                  note: noteController.text.trim(),
                  paymentMethod: paymentMethod,
                  allocations: allocations,
                ),
              );
            } catch (error) {
              setState(() => submitError = error.toString());
            }
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }
}
