import '../../models/account_transaction.dart';

class AccountLedgerIndex {
  const AccountLedgerIndex({
    required this.balanceByAccount,
    required this.transactionsByAccount,
  });

  final Map<String, double> balanceByAccount;
  final Map<String, List<AccountTransaction>> transactionsByAccount;
}

/// Read projections for customer and supplier ledger rows.
class AccountLedgerReadService {
  const AccountLedgerReadService();

  String accountKey(String accountType, String accountId) =>
      '${accountType.trim().toLowerCase()}::${accountId.trim()}';

  bool isTracked(AccountTransaction item) {
    if (item.isDeleted) return false;
    final type = item.accountType.trim().toLowerCase();
    return (type == 'customer' || type == 'supplier') &&
        item.accountId.trim().isNotEmpty;
  }

  List<AccountTransaction> activeTransactionsNewestFirst(
    Iterable<AccountTransaction> transactions,
  ) =>
      List<AccountTransaction>.unmodifiable(
        transactions
            .where((item) => !item.isDeleted)
            .toList(growable: false)
            .reversed,
      );

  AccountLedgerIndex buildIndex(Iterable<AccountTransaction> transactions) {
    final balances = <String, double>{};
    final rows = <String, List<AccountTransaction>>{};
    for (final item in transactions) {
      if (!isTracked(item)) continue;
      final key = accountKey(item.accountType, item.accountId);
      balances[key] = (balances[key] ?? 0) + item.signedAmount;
      (rows[key] ??= <AccountTransaction>[]).add(item);
    }
    for (final accountRows in rows.values) {
      accountRows.sort((a, b) => b.date.compareTo(a.date));
    }
    return AccountLedgerIndex(
      balanceByAccount: balances,
      transactionsByAccount: rows,
    );
  }

  List<AccountTransaction> transactionsForAccount({
    required String accountType,
    required String accountId,
    required Map<String, List<AccountTransaction>> index,
  }) =>
      List<AccountTransaction>.unmodifiable(
        index[accountKey(accountType, accountId)] ??
            const <AccountTransaction>[],
      );

  double accountBalance({
    required String accountType,
    required String accountId,
    required Map<String, double> balances,
  }) =>
      balances[accountKey(accountType, accountId)] ?? 0;
}
