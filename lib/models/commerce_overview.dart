class PurchasesOverview {
  const PurchasesOverview({
    required this.totalCount,
    required this.totalPurchasesAmount,
    required this.monthlyTotal,
    required this.monthlyCount,
    required this.draftTotal,
    required this.draftCount,
    required this.receivedCount,
    required this.returnedCount,
    required this.cancelledCount,
    required this.pendingPurchaseCount,
  });

  final int totalCount;
  final double totalPurchasesAmount;
  final double monthlyTotal;
  final int monthlyCount;
  final double draftTotal;
  final int draftCount;
  final int receivedCount;
  final int returnedCount;
  final int cancelledCount;
  final int pendingPurchaseCount;
}

class ExpensesOverview {
  const ExpensesOverview({
    required this.totalCount,
    required this.totalExpensesAmount,
    required this.draftCount,
    required this.postedCount,
    required this.cancelledCount,
    required this.categoryCount,
  });

  final int totalCount;
  final double totalExpensesAmount;
  final int draftCount;
  final int postedCount;
  final int cancelledCount;
  final int categoryCount;
}
