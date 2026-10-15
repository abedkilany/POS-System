part of 'accounting_page.dart';

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab(
      {required this.store, required this.query, required this.cashOnly});

  final AppStore store;
  final String query;
  final bool cashOnly;
  static final RevisionKeyCache<List<AccountTransaction>> _rowsCache =
      RevisionKeyCache<List<AccountTransaction>>();

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizedSearchQuery(query);
    final rows = _rowsCache.getOrCompute(
      store.accounting.ledgerRevision,
      '${store.runtime.identity.storeId}|$cashOnly|$normalizedQuery',
      () {
        final computed = store.accounting.transactions
            .where((txn) =>
                (!cashOnly || _isCashTxn(txn)) &&
                _matchesNormalized(normalizedQuery, [
                  txn.accountName,
                  txn.referenceNo,
                  txn.paymentMethod,
                  txn.note,
                  txn.type
                ]))
            .toList(growable: false);
        computed.sort((a, b) => b.date.compareTo(a.date));
        return computed;
      },
    );

    if (rows.isEmpty) {
      return _EmptyAccountingState(
          message: AppLocalizations.of(context).text(
              cashOnly ? 'no_cash_movements' : 'no_account_transactions'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        final rowExtent = isWide ? 72.0 : 92.0;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: isWide
              ? Column(
                  children: [
                    const _TransactionTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        scrollCacheExtent: _kAccountingListCacheExtent,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: rowExtent,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final transaction = rows[index];
                          return _TransactionRow(
                              store: store,
                              transaction: transaction,
                              isWide: isWide);
                        },
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  scrollCacheExtent: _kAccountingListCacheExtent,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemExtent: rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final transaction = rows[index];
                    return _TransactionRow(
                        store: store, transaction: transaction, isWide: isWide);
                  },
                ),
        );
      },
    );
  }

  bool _isCashTxn(AccountTransaction txn) =>
      txn.type == 'paymentReceived' ||
      txn.type == 'paymentPaid' ||
      txn.type == 'paymentReversal';
}

class _TransactionTableHeader extends StatelessWidget {
  const _TransactionTableHeader();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(color: color, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(tr.text('date'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('type'), style: style)),
          Expanded(flex: 3, child: Text(tr.text('account'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('reference'), style: style)),
          SizedBox(
              width: 118,
              child: Text(tr.text('debit'),
                  style: style, textAlign: TextAlign.end)),
          SizedBox(
              width: 118,
              child: Text(tr.text('credit'),
                  style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow(
      {required this.store, required this.transaction, required this.isWide});

  final AppStore store;
  final AccountTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final debitText = transaction.debit > 0
        ? formatUsdReferenceAmount(transaction.debit, store.runtime.profile)
        : '';
    final creditText = transaction.credit > 0
        ? formatUsdReferenceAmount(transaction.credit, store.runtime.profile)
        : '';
    final accountName = transaction.accountName.trim().isEmpty
        ? tr.text(
            transaction.accountType == 'supplier' ? 'supplier' : 'customer')
        : transaction.accountName;
    final typeText = _typeTitle(context, transaction.type);
    final methodText = transaction.paymentMethod.isEmpty
        ? ''
        : _paymentMethodLabel(context, transaction.paymentMethod);
    final note = transaction.note.trim();
    final postingLabel =
        transaction.debit > 0 ? tr.text('debit') : tr.text('credit');
    final postingAmount = transaction.debit > 0 ? debitText : creditText;

    if (!isWide) {
      return ListTile(
        leading:
            CircleAvatar(child: Icon(_iconForType(transaction.type), size: 20)),
        title: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            [
              _dateText(transaction.date),
              typeText,
              transaction.referenceNo,
              methodText,
              note,
            ].where((part) => part.trim().isNotEmpty).join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        onTap: () => _showJournalForAccountTransaction(
          context,
          store: store,
          transaction: transaction,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(postingLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(postingAmount,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _showJournalForAccountTransaction(
        context,
        store: store,
        transaction: transaction,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(_dateText(transaction.date))),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(_iconForType(transaction.type),
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(typeText,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(
                flex: 3,
                child: Text(accountName,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
                flex: 2,
                child: Text(
                    [transaction.referenceNo, methodText]
                        .where((part) => part.trim().isNotEmpty)
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            SizedBox(
                width: 118,
                child: Text(debitText,
                    textAlign: TextAlign.end,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700))),
            SizedBox(
                width: 118,
                child: Text(creditText,
                    textAlign: TextAlign.end,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'saleInvoice':
        return Icons.receipt_long_outlined;
      case 'purchaseInvoice':
        return Icons.inventory_2_outlined;
      case 'paymentReceived':
        return Icons.call_received;
      case 'paymentPaid':
        return Icons.call_made;
      case 'paymentReversal':
      case 'cancel':
        return Icons.undo_outlined;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  String _typeTitle(BuildContext context, String type) {
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

  String _paymentMethodLabel(BuildContext context, String method) {
    final tr = AppLocalizations.of(context);
    switch (method.toLowerCase()) {
      case 'cash':
        return tr.text('payment_cash');
      case 'card':
        return tr.text('payment_card');
      case 'wish':
        return tr.text('payment_wish');
      case 'check':
        return tr.text('payment_check');
      default:
        return method;
    }
  }

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
