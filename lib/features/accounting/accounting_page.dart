import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../accounts/account_ledger_widgets.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key, required this.store});

  final AppStore store;

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final metrics = _AccountingMetrics.fromStore(widget.store);

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingHeader(
            title: tr.text('accounting'),
            onRefresh: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _CompactSummaryStrip(store: widget.store, metrics: metrics),
          const SizedBox(height: 12),
          _AccountingTabs(controller: _tabController),
          const SizedBox(height: 10),
          _AccountingSearchField(controller: _searchController, query: _query),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AccountsTab(store: widget.store, query: _query, accountType: 'customer'),
                _AccountsTab(store: widget.store, query: _query, accountType: 'supplier'),
                _TransactionsTab(store: widget.store, query: _query, cashOnly: true),
                _TransactionsTab(store: widget.store, query: _query, cashOnly: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingHeader extends StatelessWidget {
  const _AccountingHeader({required this.title, required this.onRefresh});

  final String title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).text('recent_transactions'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: AppLocalizations.of(context).text('refresh'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _CompactSummaryStrip extends StatelessWidget {
  const _CompactSummaryStrip({required this.store, required this.metrics});

  final AppStore store;
  final _AccountingMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final cards = [
      _SummaryMetric(icon: Icons.people_outline, title: tr.text('customer_receivables'), amount: metrics.customerReceivables),
      _SummaryMetric(icon: Icons.local_shipping_outlined, title: tr.text('supplier_payables'), amount: metrics.supplierPayables),
      _SummaryMetric(icon: Icons.south_west, title: tr.text('today_cash_in'), amount: metrics.todayCashIn),
      _SummaryMetric(icon: Icons.north_east, title: tr.text('today_cash_out'), amount: metrics.todayCashOut),
      _SummaryMetric(icon: Icons.assignment_return_outlined, title: tr.text('customer_credits'), amount: metrics.customerCredits, subtle: true),
      _SummaryMetric(icon: Icons.inventory_outlined, title: tr.text('supplier_advances'), amount: metrics.supplierAdvances, subtle: true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(width: 220, child: _SummaryTile(store: store, metric: cards[index])),
            ),
          );
        }

        final itemWidth = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - 40) / 6
            : constraints.maxWidth >= 950
                ? (constraints.maxWidth - 24) / 4
                : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in cards) SizedBox(width: itemWidth, height: 82, child: _SummaryTile(store: store, metric: metric)),
          ],
        );
      },
    );
  }
}

class _SummaryMetric {
  const _SummaryMetric({required this.icon, required this.title, required this.amount, this.subtle = false});

  final IconData icon;
  final String title;
  final double amount;
  final bool subtle;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.store, required this.metric});

  final AppStore store;
  final _SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: metric.subtle ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.55) : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(metric.icon, size: 22, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(metric.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    formatUsdReferenceAmount(metric.amount, store.storeProfile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingTabs extends StatelessWidget {
  const _AccountingTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.person_outline), text: tr.text('customers')),
            Tab(icon: const Icon(Icons.local_shipping_outlined), text: tr.text('suppliers')),
            Tab(icon: const Icon(Icons.payments_outlined), text: tr.text('cash_movement')),
            Tab(icon: const Icon(Icons.history_outlined), text: tr.text('recent_transactions')),
          ],
        ),
      ),
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
        suffixIcon: query.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: controller.clear),
      ),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({required this.store, required this.query, required this.accountType});

  final AppStore store;
  final String query;
  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final rows = accountType == 'customer'
        ? store.customers
            .where((customer) => _matches(query, [customer.name, customer.phone, customer.address]))
            .map((customer) => _AccountRowData(
                  id: customer.id,
                  name: customer.name,
                  subtitle: [customer.phone, customer.address].where((part) => part.trim().isNotEmpty).join(' • '),
                  balance: store.accountBalance('customer', customer.id),
                ))
            .toList()
        : store.suppliers
            .where((supplier) => _matches(query, [supplier.name, supplier.nameEn, supplier.nameAr, supplier.phone, supplier.address]))
            .map((supplier) => _AccountRowData(
                  id: supplier.id,
                  name: supplier.name,
                  subtitle: [supplier.phone, supplier.address].where((part) => part.trim().isNotEmpty).join(' • '),
                  balance: store.accountBalance('supplier', supplier.id),
                ))
            .toList();
    rows.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

    if (rows.isEmpty) {
      return _EmptyAccountingState(message: tr.text(accountType == 'customer' ? 'no_customers_found' : 'no_suppliers_found'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            itemCount: rows.length + (isWide ? 1 : 0),
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (isWide && index == 0) return _AccountTableHeader(accountType: accountType);
              final row = rows[isWide ? index - 1 : index];
              return _AccountListRow(store: store, accountType: accountType, row: row, isWide: isWide);
            },
          ),
        );
      },
    );
  }
}

class _AccountRowData {
  const _AccountRowData({required this.id, required this.name, required this.subtitle, required this.balance});

  final String id;
  final String name;
  final String subtitle;
  final double balance;
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader({required this.accountType});

  final String accountType;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(tr.text(accountType == 'customer' ? 'customer' : 'supplier'), style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Text(tr.text('balance'), style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          const SizedBox(width: 260),
        ],
      ),
    );
  }
}

class _AccountListRow extends StatelessWidget {
  const _AccountListRow({required this.store, required this.accountType, required this.row, required this.isWide});

  final AppStore store;
  final String accountType;
  final _AccountRowData row;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = accountBalanceColor(context, store, accountType, row.id);
    final actions = [
      OutlinedButton.icon(
        onPressed: () => showAccountLedgerSheet(context: context, store: store, accountType: accountType, accountId: row.id, accountName: row.name),
        icon: const Icon(Icons.list_alt_outlined, size: 18),
        label: Text(tr.text('account_ledger')),
      ),
      FilledButton.icon(
        onPressed: () => showAccountPaymentDialog(context: context, store: store, accountType: accountType, accountId: row.id, accountName: row.name),
        icon: Icon(accountType == 'customer' ? Icons.call_received : Icons.call_made, size: 18),
        label: Text(accountType == 'customer' ? tr.text('receive_payment') : tr.text('pay_supplier')),
      ),
    ];

    if (!isWide) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 18, child: Icon(accountType == 'customer' ? Icons.person_outline : Icons.local_shipping_outlined, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(formatUsdReferenceAmount(row.balance.abs(), store.storeProfile), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(radius: 17, child: Icon(accountType == 'customer' ? Icons.person_outline : Icons.local_shipping_outlined, size: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (row.subtitle.isNotEmpty)
                        Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(formatUsdReferenceAmount(row.balance.abs(), store.storeProfile), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 260,
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
          ),
        ],
      ),
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab({required this.store, required this.query, required this.cashOnly});

  final AppStore store;
  final String query;
  final bool cashOnly;

  @override
  Widget build(BuildContext context) {
    final rows = store.accountTransactions
        .where((txn) => (!cashOnly || _isCashTxn(txn)) && _matches(query, [txn.accountName, txn.referenceNo, txn.paymentMethod, txn.note, txn.type]))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (rows.isEmpty) {
      return _EmptyAccountingState(message: AppLocalizations.of(context).text(cashOnly ? 'no_cash_movements' : 'no_account_transactions'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            itemCount: rows.length + (isWide ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (isWide && index == 0) return const _TransactionTableHeader();
              final transaction = rows[isWide ? index - 1 : index];
              return _TransactionRow(store: store, transaction: transaction, isWide: isWide);
            },
          ),
        );
      },
    );
  }

  bool _isCashTxn(AccountTransaction txn) => txn.type == 'paymentReceived' || txn.type == 'paymentPaid' || txn.type == 'paymentReversal';
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(tr.text('date'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('type'), style: style)),
          Expanded(flex: 3, child: Text(tr.text('account'), style: style)),
          Expanded(flex: 2, child: Text(tr.text('reference'), style: style)),
          SizedBox(width: 130, child: Text(tr.text('amount'), style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.store, required this.transaction, required this.isWide});

  final AppStore store;
  final AccountTransaction transaction;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final amount = transaction.debit > 0 ? transaction.debit : transaction.credit;
    final sign = _displaySign(transaction);
    final amountText = '$sign ${formatUsdReferenceAmount(amount, store.storeProfile)}';
    final accountName = transaction.accountName.trim().isEmpty ? tr.text(transaction.accountType == 'supplier' ? 'supplier' : 'customer') : transaction.accountName;
    final typeText = _typeTitle(context, transaction.type);
    final methodText = transaction.paymentMethod.isEmpty ? '' : _paymentMethodLabel(context, transaction.paymentMethod);
    final note = transaction.note.trim();
    final color = sign == '+' ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error;

    if (!isWide) {
      return ListTile(
        leading: CircleAvatar(child: Icon(_iconForType(transaction.type), size: 20)),
        title: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          _dateText(transaction.date),
          typeText,
          transaction.referenceNo,
          methodText,
          note,
        ].where((part) => part.trim().isNotEmpty).join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(amountText, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(_dateText(transaction.date))),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(_iconForType(transaction.type), size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(typeText, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text([transaction.referenceNo, methodText].where((part) => part.trim().isNotEmpty).join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 130, child: Text(amountText, textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  String _displaySign(AccountTransaction transaction) {
    if (transaction.type == 'paymentReceived') return '+';
    if (transaction.type == 'paymentPaid') return '-';
    if (transaction.type == 'paymentReversal' && transaction.accountType == 'supplier') return '+';
    if (transaction.type == 'paymentReversal' && transaction.accountType == 'customer') return '-';
    return transaction.debit > 0 ? '+' : '-';
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

  String _dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _EmptyAccountingState extends StatelessWidget {
  const _EmptyAccountingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _AccountingMetrics {
  const _AccountingMetrics({
    required this.customerReceivables,
    required this.customerCredits,
    required this.supplierPayables,
    required this.supplierAdvances,
    required this.todayCashIn,
    required this.todayCashOut,
  });

  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
  final double todayCashIn;
  final double todayCashOut;

  factory _AccountingMetrics.fromStore(AppStore store) {
    final customers = store.customers;
    final suppliers = store.suppliers;
    final accountTransactions = store.accountTransactions;
    final customerReceivables = customers.fold<double>(0, (sum, customer) {
      final balance = store.accountBalance('customer', customer.id);
      return balance > 0 ? sum + balance : sum;
    });
    final customerCredits = customers.fold<double>(0, (sum, customer) {
      final balance = store.accountBalance('customer', customer.id);
      return balance < 0 ? sum + balance.abs() : sum;
    });
    final supplierPayables = suppliers.fold<double>(0, (sum, supplier) {
      final balance = store.accountBalance('supplier', supplier.id);
      return balance < 0 ? sum + balance.abs() : sum;
    });
    final supplierAdvances = suppliers.fold<double>(0, (sum, supplier) {
      final balance = store.accountBalance('supplier', supplier.id);
      return balance > 0 ? sum + balance : sum;
    });
    final today = DateTime.now();
    final todayCashIn = accountTransactions.where((txn) => _sameDay(txn.date, today) && _isCashIn(txn)).fold<double>(0, (sum, txn) => sum + _cashAmount(txn));
    final todayCashOut = accountTransactions.where((txn) => _sameDay(txn.date, today) && _isCashOut(txn)).fold<double>(0, (sum, txn) => sum + _cashAmount(txn));
    return _AccountingMetrics(
      customerReceivables: customerReceivables,
      customerCredits: customerCredits,
      supplierPayables: supplierPayables,
      supplierAdvances: supplierAdvances,
      todayCashIn: todayCashIn,
      todayCashOut: todayCashOut,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static bool _isCashIn(AccountTransaction txn) => txn.type == 'paymentReceived' || (txn.type == 'paymentReversal' && txn.accountType == 'supplier');
  static bool _isCashOut(AccountTransaction txn) => txn.type == 'paymentPaid' || (txn.type == 'paymentReversal' && txn.accountType == 'customer');
  static double _cashAmount(AccountTransaction txn) => txn.debit > 0 ? txn.debit : txn.credit;
}

bool _matches(String query, List<String?> values) {
  if (query.trim().isEmpty) return true;
  return values.whereType<String>().any((value) => value.toLowerCase().contains(query));
}
