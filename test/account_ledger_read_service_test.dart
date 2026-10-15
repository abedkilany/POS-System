import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/account_ledger_read_service.dart';
import 'package:ventio/models/account_transaction.dart';

void main() {
  const service = AccountLedgerReadService();
  final older = DateTime(2026, 1, 1);
  final newer = DateTime(2026, 1, 2);
  final transactions = <AccountTransaction>[
    AccountTransaction(
      id: 'older-credit',
      accountType: ' Customer ',
      accountId: ' c1 ',
      accountName: 'Customer',
      date: older,
      type: 'sale',
      referenceId: 'sale-1',
      referenceNo: '1',
      credit: 10,
    ),
    AccountTransaction(
      id: 'newer-debit',
      accountType: 'customer',
      accountId: 'c1',
      accountName: 'Customer',
      date: newer,
      type: 'payment',
      referenceId: 'payment-1',
      referenceNo: '2',
      debit: 4,
    ),
    AccountTransaction(
      id: 'deleted',
      accountType: 'customer',
      accountId: 'c1',
      accountName: 'Customer',
      date: newer,
      type: 'sale',
      referenceId: 'sale-2',
      referenceNo: '3',
      debit: 99,
      deletedAt: newer,
    ),
    AccountTransaction(
      id: 'cash-ledger',
      accountType: 'cash',
      accountId: 'cash-1',
      accountName: 'Cash',
      date: newer,
      type: 'cash',
      referenceId: 'cash-1',
      referenceNo: '4',
      debit: 100,
    ),
  ];

  test('indexes active customer and supplier rows with normalized keys', () {
    final index = service.buildIndex(transactions);
    expect(
      service.accountBalance(
        accountType: ' CUSTOMER ',
        accountId: 'c1 ',
        balances: index.balanceByAccount,
      ),
      -6,
    );
    final rows = service.transactionsForAccount(
      accountType: 'customer',
      accountId: ' c1',
      index: index.transactionsByAccount,
    );
    expect(
        rows.map((item) => item.id), <String>['newer-debit', 'older-credit']);
    expect(() => rows.add(transactions.first), throwsUnsupportedError);
    expect(
      service.accountBalance(
        accountType: 'cash',
        accountId: 'cash-1',
        balances: index.balanceByAccount,
      ),
      0,
    );
  });

  test('keeps active account transactions newest first', () {
    expect(
      service
          .activeTransactionsNewestFirst(transactions)
          .map((item) => item.id),
      <String>['cash-ledger', 'newer-debit', 'older-credit'],
    );
  });
}
