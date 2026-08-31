part of 'app_store.dart';

extension _AppStorePurchaseInsights on AppStore {
  PurchasesOverview get _purchasesOverviewImpl {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month}';
    if (_cachedPurchasesOverviewRevision == _purchasesRevision &&
        _cachedPurchasesOverviewMonthKey == monthKey &&
        _cachedPurchasesOverview != null) {
      return _cachedPurchasesOverview!;
    }
    var totalCount = 0;
    var totalPurchasesAmount = 0.0;
    var monthlyTotal = 0.0;
    var monthlyCount = 0;
    var draftTotal = 0.0;
    var draftCount = 0;
    var receivedCount = 0;
    var returnedCount = 0;
    var cancelledCount = 0;

    for (final purchase in _purchases) {
      if (purchase.isDeleted) continue;
      totalCount += 1;
      final isCancelled = purchase.isCancelled;
      final isReceived = purchase.isReceived;
      final isReturned = purchase.isReturned;
      if (!isReceived && !isCancelled) draftCount += 1;
      if (isReceived && !isReturned) receivedCount += 1;
      if (isReturned) returnedCount += 1;
      if (purchase.status.toLowerCase() == 'cancelled') {
        cancelledCount += 1;
      }
      if (isCancelled) continue;
      totalPurchasesAmount += purchase.subtotal;
      if (purchase.date.year == now.year && purchase.date.month == now.month) {
        monthlyTotal += purchase.subtotal;
        monthlyCount += 1;
      }
      if (!isReceived) {
        draftTotal += purchase.subtotal;
      }
    }

    _cachedPurchasesOverview = PurchasesOverview(
      totalCount: totalCount,
      totalPurchasesAmount: totalPurchasesAmount,
      monthlyTotal: monthlyTotal,
      monthlyCount: monthlyCount,
      draftTotal: draftTotal,
      draftCount: draftCount,
      receivedCount: receivedCount,
      returnedCount: returnedCount,
      cancelledCount: cancelledCount,
      pendingPurchaseCount: draftCount,
    );
    _cachedPurchasesOverviewRevision = _purchasesRevision;
    _cachedPurchasesOverviewMonthKey = monthKey;
    return _cachedPurchasesOverview!;
  }

  void _ensurePurchaseInsightsCacheImpl() {
    if (!_purchaseInsightsCacheDirty) return;
    _purchaseHistoryByProductCache.clear();
    _purchaseMetricsByProductCache.clear();

    for (final purchase in _purchases.where(
      (item) => !item.isDeleted && !item.isCancelled,
    )) {
      for (final item in purchase.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        (_purchaseHistoryByProductCache[productId] ??=
                <SupplierPurchasePrice>[])
            .add(
          SupplierPurchasePrice(
            productId: item.productId,
            productName: item.productName,
            supplierId: purchase.supplierId,
            supplierName: purchase.supplierName,
            unitCost: item.unitCostPerBase,
            quantity: item.baseQuantity,
            purchaseId: purchase.id,
            purchaseNo: purchase.purchaseNo,
            date: purchase.date,
          ),
        );
      }
    }

    for (final entry in _purchaseHistoryByProductCache.entries) {
      final history = entry.value..sort((a, b) => b.date.compareTo(a.date));
      double totalQty = 0;
      double totalCost = 0;
      final suppliers = <String>{};
      for (final row in history) {
        totalQty += row.quantity;
        totalCost += row.quantity * row.unitCost;
        if (row.supplierId.trim().isNotEmpty) suppliers.add(row.supplierId);
      }
      _purchaseMetricsByProductCache[entry.key] = _ProductPurchaseMetrics(
        lastCost: history.isEmpty ? null : history.first.unitCost,
        averageCost: totalQty <= 0 ? 0 : totalCost / totalQty,
        supplierCount: suppliers.length,
      );
    }

    _purchaseInsightsCacheDirty = false;
  }

  List<SupplierPurchasePrice> _purchasePriceHistoryForProductImpl(
    String productId,
  ) {
    _ensurePurchaseInsightsCacheImpl();
    return List.unmodifiable(
      _purchaseHistoryByProductCache[productId] ??
          const <SupplierPurchasePrice>[],
    );
  }

  List<SupplierPurchasePrice> _supplierPriceComparisonForProductImpl(
    String productId,
  ) {
    _ensurePurchaseInsightsCacheImpl();
    final latestBySupplier = <String, SupplierPurchasePrice>{};
    for (final entry in _purchaseHistoryByProductCache[productId] ??
        const <SupplierPurchasePrice>[]) {
      latestBySupplier.putIfAbsent(entry.supplierId, () => entry);
    }
    final prices = latestBySupplier.values.toList()
      ..sort((a, b) => a.unitCost.compareTo(b.unitCost));
    return List.unmodifiable(prices);
  }

  double? _lastPurchasePriceForImpl({
    required String productId,
    required String supplierId,
  }) {
    _ensurePurchaseInsightsCacheImpl();
    for (final entry in _purchaseHistoryByProductCache[productId] ??
        const <SupplierPurchasePrice>[]) {
      if (entry.supplierId == supplierId) return entry.unitCost;
    }
    return null;
  }

  double? _lastPurchasePriceForProductImpl(String productId) {
    _ensurePurchaseInsightsCacheImpl();
    return _purchaseMetricsByProductCache[productId]?.lastCost;
  }

  PurchaseItem? _lastPurchaseItemForImpl({
    required String productId,
    required String supplierId,
  }) {
    final sortedPurchases = _purchases
        .where(
          (purchase) =>
              !purchase.isDeleted &&
              !purchase.isCancelled &&
              purchase.supplierId == supplierId,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId == productId) return item;
      }
    }
    return null;
  }

  PurchaseItem? _lastPurchaseItemForProductImpl(String productId) {
    final sortedPurchases = _purchases
        .where((purchase) => !purchase.isDeleted && !purchase.isCancelled)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final purchase in sortedPurchases) {
      for (final item in purchase.items) {
        if (item.productId == productId) return item;
      }
    }
    return null;
  }

  double _averagePurchaseCostForProductImpl(String productId) {
    _ensurePurchaseInsightsCacheImpl();
    return _purchaseMetricsByProductCache[productId]?.averageCost ?? 0;
  }
}
