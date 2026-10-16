import '../../models/account_transaction.dart';

/// Session-local cache state. SQLite remains authoritative.
class AccountingState {
  final List<AccountTransaction> accountTransactions = [];
  final Map<String, int> accountTransactionIndexById = <String, int>{};
  final Map<String, double> accountBalanceCache = <String, double>{};
  final Map<String, List<AccountTransaction>>
      accountTransactionsByAccountCache = <String, List<AccountTransaction>>{};
  bool accountLedgerCacheDirty = true;
  final Map<String, Future<bool>> pendingPurchaseAccountingTasks =
      <String, Future<bool>>{};
  Future<void> purchaseAccountingQueue = Future<void>.value();
  DateTime? phase8AccountingSyncCursor;
  bool phase8AccountingSyncCaptureInFlight = false;
  bool phase8AccountingSyncCapturePending = false;
}
