part of 'app_store.dart';

extension _AppStoreSplitCatalogPartiesExpensesPart4 on AppStore {
  Future<void> permanentlyDeleteCancelledExpense(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (!expense.isCancelled) {
      throw StateError('Only cancelled expenses can reach this audit guard.');
    }
    throw StateError(
      'Posted/cancelled expenses are retained for audit and cannot be permanently deleted. Use reversal/correction instead.',
    );
  }
}
