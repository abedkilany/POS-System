part of 'accounting_page.dart';

class _CashLedgerTransactionsTab extends StatefulWidget {
  const _CashLedgerTransactionsTab({required this.store, required this.query});

  final ApplicationSession store;
  final String query;

  @override
  State<_CashLedgerTransactionsTab> createState() =>
      _CashLedgerTransactionsTabState();
}

class _CashLedgerTransactionsTabState
    extends State<_CashLedgerTransactionsTab> {
  late Future<List<CashLedgerTransaction>> _future;
  int _lastSeenRevision = -1;
  String _direction = '';
  String _type = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _lastSeenRevision = widget.store.accounting.revision;
    widget.store.addListener(_handleStoreChanged);
    final now = DateTime.now().toLocal();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
    _reload();
  }

  @override
  void didUpdateWidget(covariant _CashLedgerTransactionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
      _lastSeenRevision = widget.store.accounting.revision;
      _reload();
      return;
    }
    if (oldWidget.query != widget.query) {
      _reload();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    final revision = widget.store.accounting.revision;
    if (revision == _lastSeenRevision) return;
    _lastSeenRevision = revision;
    setState(_reload);
  }

  void _reload() {
    try {
      _future = CashLedgerService.current().list(
        search: widget.query.trim(),
        direction: _direction,
        type: _type,
        from: _from,
        to: _to,
        limit: 500,
      );
    } catch (error, stackTrace) {
      _future = Future<List<CashLedgerTransaction>>.error(error, stackTrace);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now().toLocal();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(
        start: _from ?? DateTime(now.year, now.month, 1),
        end: _to ?? now,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
        999,
      );
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CashLedgerFilterBar(
          direction: _direction,
          type: _type,
          from: _from,
          to: _to,
          onDirectionChanged: (value) => setState(() {
            _direction = value;
            _reload();
          }),
          onTypeChanged: (value) => setState(() {
            _type = value;
            _reload();
          }),
          onPickRange: _pickRange,
          onClearRange: () => setState(() {
            _from = null;
            _to = null;
            _reload();
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<CashLedgerTransaction>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator.adaptive());
              }
              if (snapshot.hasError) {
                return _ReportError(message: snapshot.error.toString());
              }
              final rows = snapshot.data ?? const <CashLedgerTransaction>[];
              if (rows.isEmpty) {
                return _EmptyAccountingState(
                  message:
                      AppLocalizations.of(context).text('no_cash_movements'),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: isWide
                        ? Column(
                            children: [
                              const _CashLedgerTableHeader(),
                              Expanded(
                                child: ListView.builder(
                                  scrollCacheExtent:
                                      _kAccountingListCacheExtent,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  itemExtent: 74,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) =>
                                      _CashLedgerTransactionRow(
                                    store: widget.store,
                                    transaction: rows[index],
                                    isWide: true,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            scrollCacheExtent: _kAccountingListCacheExtent,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemExtent: 96,
                            itemCount: rows.length,
                            itemBuilder: (context, index) =>
                                _CashLedgerTransactionRow(
                              store: widget.store,
                              transaction: rows[index],
                              isWide: false,
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CashLedgerFilterBar extends StatelessWidget {
  const _CashLedgerFilterBar({
    required this.direction,
    required this.type,
    required this.from,
    required this.to,
    required this.onDirectionChanged,
    required this.onTypeChanged,
    required this.onPickRange,
    required this.onClearRange,
  });

  final String direction;
  final String type;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = from == null || to == null
        ? _accountingUiText(
            context, 'كل الفترات', 'All periods', 'Toutes périodes')
        : '${_dateText(from!)} → ${_dateText(to!)}';
    const types = <String>[
      'receipt',
      'payment',
      'supplier_payment',
      'expense',
      'refund',
      'supplier_refund',
      'expense_refund',
      'cash_in',
      'cash_out',
      'cash_deposit',
      'cash_withdrawal',
      'transfer',
      'vault_transfer',
      'shift_transfer',
      'shortage',
      'overage',
      'opening',
      'closing',
      'reversal',
    ];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey('cash-direction:$direction'),
                initialValue: direction,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'الاتجاه', 'Direction', 'Sens'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(context, 'داخل وخارج',
                        'In & out', 'Entrées et sorties')),
                  ),
                  DropdownMenuItem(
                    value: 'in',
                    child: Text(AppLocalizations.of(context).text('cash_in')),
                  ),
                  DropdownMenuItem(
                    value: 'out',
                    child: Text(AppLocalizations.of(context).text('cash_out')),
                  ),
                ],
                onChanged: (value) => onDirectionChanged(value ?? ''),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                key: ValueKey('cash-type:$type'),
                initialValue: type,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _accountingUiText(
                      context, 'نوع الحركة', 'Movement type', 'Type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(_accountingUiText(
                        context, 'كل الأنواع', 'All types', 'Tous les types')),
                  ),
                  for (final value in types)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_cashLedgerTypeLabel(context, value)),
                    ),
                ],
                onChanged: (value) => onTypeChanged(value ?? ''),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            if (from != null || to != null)
              TextButton.icon(
                onPressed: onClearRange,
                icon: const Icon(Icons.clear),
                label: Text(_accountingUiText(
                    context, 'كل الفترات', 'All periods', 'Toutes périodes')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashLedgerTableHeader extends StatelessWidget {
  const _CashLedgerTableHeader();

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final style = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
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
            width: 120,
            child: Text(
              tr.text('cash_in'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              tr.text('cash_out'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashLedgerTransactionRow extends StatelessWidget {
  const _CashLedgerTransactionRow({
    required this.store,
    required this.transaction,
    required this.isWide,
  });

  final ApplicationSession store;
  final CashLedgerTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isIn = transaction.isCashIn;
    final amountText = formatUsdReferenceAmount(
      transaction.amount,
      store.runtime.profile,
    );
    final party = transaction.partyName.trim().isNotEmpty
        ? transaction.partyName.trim()
        : transaction.notes.trim().isNotEmpty
            ? transaction.notes.trim()
            : _cashLedgerPartyFallback(context, transaction.partyType);
    final reference = _joinParts([
      transaction.referenceNumber,
      transaction.paymentMethod,
    ]);
    final typeLabel = _cashLedgerTypeLabel(context, transaction.type);
    final directionLabel = tr.text(isIn ? 'cash_in' : 'cash_out');
    final directionColor = isIn
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    if (!isWide) {
      return ListTile(
        leading: CircleAvatar(
          child: Icon(
            isIn ? Icons.south_west : Icons.north_east,
            size: 20,
          ),
        ),
        title: Text(
          party.isEmpty ? typeLabel : party,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            _dateText(transaction.occurredAt.toLocal()),
            typeLabel,
            reference,
          ].where((part) => part.trim().isNotEmpty).join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _showJournalForCashLedgerTransaction(
          context,
          store: store,
          transaction: transaction,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              directionLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: directionColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              amountText,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: directionColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _showJournalForCashLedgerTransaction(
        context,
        store: store,
        transaction: transaction,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(_dateText(transaction.occurredAt.toLocal())),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(
                    isIn ? Icons.south_west : Icons.north_east,
                    size: 18,
                    color: directionColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                party,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                reference,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                isIn ? amountText : '',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isIn ? directionColor : null,
                      fontWeight: isIn ? FontWeight.w800 : null,
                    ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                isIn ? '' : amountText,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isIn ? null : directionColor,
                      fontWeight: isIn ? null : FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cashLedgerPartyFallback(BuildContext context, String partyType) {
  final tr = AppLocalizations.of(context);
  switch (partyType.trim().toLowerCase()) {
    case 'customer':
      return tr.text('customer');
    case 'supplier':
      return tr.text('supplier');
    default:
      return '';
  }
}

String _cashLedgerTypeLabel(BuildContext context, String type) {
  final language = Localizations.localeOf(context).languageCode;
  final normalized = type.trim().toLowerCase();
  const ar = <String, String>{
    'receipt': 'قبض',
    'payment': 'دفع',
    'expense': 'مصروف نقدي',
    'refund': 'استرداد عميل',
    'supplier_refund': 'استرداد مورد',
    'expense_refund': 'استرداد مصروف',
    'supplier_payment': 'دفع مورد',
    'cash_in': 'إيداع نقدي',
    'cash_out': 'سحب نقدي',
    'cash_deposit': 'إيداع نقدي',
    'cash_withdrawal': 'سحب نقدي',
    'deposit': 'إيداع نقدي',
    'withdrawal': 'سحب نقدي',
    'transfer': 'تحويل نقدي',
    'vault_transfer': 'تحويل خزنة',
    'shift_transfer': 'تحويل وردية',
    'transfer_in': 'تحويل وارد',
    'transfer_out': 'تحويل صادر',
    'shortage': 'عجز صندوق',
    'overage': 'زيادة صندوق',
    'opening': 'افتتاح',
    'closing': 'إغلاق',
    'reversal': 'عكس حركة',
  };
  const en = <String, String>{
    'receipt': 'Receipt',
    'payment': 'Payment',
    'expense': 'Cash expense',
    'refund': 'Customer refund',
    'supplier_refund': 'Supplier refund',
    'expense_refund': 'Expense refund',
    'supplier_payment': 'Supplier payment',
    'cash_in': 'Cash deposit',
    'cash_out': 'Cash withdrawal',
    'cash_deposit': 'Cash deposit',
    'cash_withdrawal': 'Cash withdrawal',
    'deposit': 'Cash deposit',
    'withdrawal': 'Cash withdrawal',
    'transfer': 'Cash transfer',
    'vault_transfer': 'Vault transfer',
    'shift_transfer': 'Shift transfer',
    'transfer_in': 'Transfer in',
    'transfer_out': 'Transfer out',
    'shortage': 'Cash shortage',
    'overage': 'Cash overage',
    'opening': 'Opening',
    'closing': 'Closing',
    'reversal': 'Reversal',
  };
  final label = language == 'ar' ? ar[normalized] : en[normalized];
  if (label != null) return label;
  return type.replaceAll('_', ' ').trim();
}

Future<void> _showJournalForCashLedgerTransaction(
  BuildContext context, {
  required ApplicationSession store,
  required CashLedgerTransaction transaction,
}) async {
  final referenceType = transaction.referenceType.trim();
  final referenceId = transaction.referenceId.trim();
  await _showJournalDrillDown(
    context,
    store: store,
    referenceType: referenceType,
    referenceId: referenceId,
    referenceNo: transaction.referenceNumber,
  );
}

Future<void> _showJournalForAccountTransaction(
  BuildContext context, {
  required ApplicationSession store,
  required AccountTransaction transaction,
}) async {
  String referenceType = '';
  String referenceId = '';
  switch (transaction.type) {
    case 'saleInvoice':
      referenceType = 'sale';
      referenceId = transaction.referenceId;
      break;
    case 'purchaseInvoice':
      referenceType = 'purchase';
      referenceId = transaction.referenceId;
      break;
    case 'paymentReceived':
      referenceType = 'receipt_voucher';
      referenceId = _voucherIdFromAccountTransaction(
        transaction.id,
        const ['-customer-payment', '-customer-account-payment'],
      );
      break;
    case 'paymentPaid':
      referenceType = 'payment_voucher';
      referenceId = _voucherIdFromAccountTransaction(
        transaction.id,
        const ['-supplier-payment', '-supplier-account-payment'],
      );
      break;
    case 'saleReturn':
      referenceType = 'sale_return';
      break;
    case 'expense':
      referenceType = 'expense';
      referenceId = transaction.referenceId;
      break;
    default:
      break;
  }
  await _showJournalDrillDown(
    context,
    store: store,
    referenceType: referenceType,
    referenceId: referenceId,
    referenceNo: transaction.referenceNo,
  );
}

String _voucherIdFromAccountTransaction(String id, List<String> suffixes) {
  for (final suffix in suffixes) {
    if (id.endsWith(suffix) && id.length > suffix.length) {
      return id.substring(0, id.length - suffix.length);
    }
  }
  return '';
}
