part of 'dashboard_snapshot_service.dart';

extension DashboardSnapshotServiceMethods2 on DashboardSnapshotService {
  Future<Map<String, Object?>> _computeSnapshotFromStore(
    AppStore store,
    DateTime reference,
  ) async {
    final today = DateTime(reference.year, reference.month, reference.day);
    final start7 = today.subtract(const Duration(days: 6));
    final start30 = today.subtract(const Duration(days: 29));

    final products = store.catalog.products;
    final sales = store.commerce.sales;
    final purchases = store.commerce.purchases;
    final expenses = store.commerce.expenses;
    final stockMovements = store.inventory.stockMovements;
    final accountTransactions = store.accounting.transactions;
    final syncQueue = store.sync.queue;

    final sales7 = DashboardSnapshotService._dateMap(start7, 7);
    final sales30 = DashboardSnapshotService._dateMap(start30, 30);
    final topProducts = <String, double>{};
    final topCustomers = <String, double>{};
    final expenseCategories = <String, double>{};
    final recentOps = <Map<String, Object?>>[];
    final recentStockMovements = <Map<String, Object?>>[];
    final lowStockNames = <String>[];
    final codeCounts = <String, int>{};
    final barcodeCounts = <String, int>{};

    var todaySalesTotal = 0.0;
    var todayProfitTotal = 0.0;
    var todayInvoiceCount = 0;
    var salesSince30Days = 0.0;
    var profitSince30Days = 0.0;
    var totalPurchasesAmount = 0.0;
    var totalExpensesAmount = 0.0;
    var inventoryCostValue = 0.0;
    Map<String, ProductCostSnapshot> inventoryCostSnapshots =
        const <String, ProductCostSnapshot>{};
    try {
      inventoryCostSnapshots = await store.catalog.productCostSnapshotsForProducts(
        products.where((product) => product.trackStock && !product.isDeleted),
      );
    } catch (_) {
      // Keep the in-memory fallback available if SQLite valuation is
      // temporarily unavailable. The DB-first dashboard path remains primary.
    }
    var lowStockCount = 0;
    var pendingSyncCount = 0;
    var todayExpenseTotal = 0.0;
    final expenseDailyTotals = <String, double>{};

    for (final product in products) {
      if (product.isDeleted) continue;
      final code = product.code.trim().toLowerCase();
      if (code.isNotEmpty) {
        codeCounts[code] = (codeCounts[code] ?? 0) + 1;
      }
      final barcode = product.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        barcodeCounts[barcode] = (barcodeCounts[barcode] ?? 0) + 1;
      }
      if (!product.trackStock) continue;
      final stock = product.stock;
      final costSnapshot = inventoryCostSnapshots[product.id];
      inventoryCostValue += costSnapshot != null && costSnapshot.hasInventory
          ? costSnapshot.currentInventoryUnitCost *
              costSnapshot.inventoryQuantity
          : product.usdCost * stock;
      if (stock <= product.lowStockThreshold) {
        lowStockCount += 1;
        final name =
            product.name.trim().isEmpty ? 'Product' : product.name.trim();
        lowStockNames.add(name);
      }
    }
    await Future<void>.delayed(Duration.zero);

    for (final sale in sales) {
      if (sale.isDeleted || sale.isCancelled) continue;
      final date = sale.date;
      final day = DateTime(date.year, date.month, date.day);
      final total = sale.effectiveTransactionAmount > 0
          ? sale.effectiveTransactionAmount
          : sale.total;
      final grossProfit = sale.grossProfit;
      if (DashboardSnapshotService._isSameDay(day, today)) {
        todaySalesTotal += total;
        todayProfitTotal += grossProfit;
        todayInvoiceCount += 1;
      }
      if (!day.isBefore(start30)) {
        salesSince30Days += total;
        profitSince30Days += grossProfit;
      }
      final key = DashboardSnapshotService._dateKey(day);
      if (sales7.containsKey(key)) sales7[key] = (sales7[key] ?? 0) + total;
      if (sales30.containsKey(key)) sales30[key] = (sales30[key] ?? 0) + total;
      final customerName = sale.customerName.trim().isEmpty
          ? 'Walk-in customer'
          : sale.customerName.trim();
      topCustomers[customerName] = (topCustomers[customerName] ?? 0) + total;
      for (final item in sale.items) {
        final name = item.productName.trim();
        if (name.isEmpty) continue;
        topProducts[name] = (topProducts[name] ?? 0) + item.quantity;
      }
      recentOps.add(<String, Object?>{
        'type': 'sale',
        'title': sale.invoiceNo,
        'subtitle': customerName,
        'amount': total,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final purchase in purchases) {
      if (purchase.isDeleted || purchase.isCancelled) continue;
      final date = purchase.date;
      final subtotal = purchase.subtotal;
      totalPurchasesAmount += subtotal;
      recentOps.add(<String, Object?>{
        'type': 'purchase',
        'title': purchase.purchaseNo,
        'subtitle': purchase.supplierName.trim().isEmpty
            ? 'Purchase'
            : purchase.supplierName.trim(),
        'amount': subtotal,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final expense in expenses) {
      if (expense.isDeleted || !expense.isPosted) continue;
      final date = expense.date;
      final amount = expense.amount;
      totalExpensesAmount += amount;
      final category = expense.category.trim().isEmpty
          ? 'Unspecified'
          : expense.category.trim();
      expenseCategories[category] = (expenseCategories[category] ?? 0) + amount;
      final key = DashboardSnapshotService._dateKey(DateTime(date.year, date.month, date.day));
      expenseDailyTotals[key] = (expenseDailyTotals[key] ?? 0) + amount;
      if (DashboardSnapshotService._isSameDay(date, today)) {
        todayExpenseTotal += amount;
      }
      recentOps.add(<String, Object?>{
        'type': 'expense',
        'title': expense.title,
        'subtitle': category,
        'amount': amount,
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final raw in stockMovements) {
      final date = raw.date;
      final qty = raw.quantity;
      recentStockMovements.add(<String, Object?>{
        'type': raw.type,
        'title': raw.productName.isEmpty ? 'Movement' : raw.productName,
        'subtitle': raw.referenceNo,
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
      recentOps.add(<String, Object?>{
        'type': 'stockMovement',
        'title': raw.type.isEmpty ? 'Movement' : raw.type,
        'subtitle': raw.productName,
        'amount': qty.abs(),
        'at': date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final txn in accountTransactions) {
      if (txn.isDeleted) continue;
      recentOps.add(<String, Object?>{
        'type': 'payment',
        'title': txn.referenceNo.isEmpty
            ? (txn.type.isEmpty ? 'Payment' : txn.type)
            : txn.referenceNo,
        'subtitle': txn.accountName,
        'amount': (txn.debit - txn.credit).abs(),
        'at': txn.date.toIso8601String(),
      });
    }
    await Future<void>.delayed(Duration.zero);

    for (final item in syncQueue) {
      if (item.isPending) pendingSyncCount += 1;
    }

    recentOps.sort((a, b) {
      final aDate = DateTime.tryParse(a['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final duplicateCodeCount =
        codeCounts.values.where((count) => count > 1).length;
    final duplicateBarcodeCount =
        barcodeCounts.values.where((count) => count > 1).length;
    final expenseList = expenseCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProductList = topProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCustomerList = topCustomers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return <String, Object?>{
      'todaySalesTotal': todaySalesTotal,
      'todayProfitTotal': todayProfitTotal,
      'todayInvoiceCount': todayInvoiceCount,
      'salesSince30Days': salesSince30Days,
      'profitSince30Days': profitSince30Days,
      'salesLast7Days': sales7.entries
          .map((entry) => <String, Object?>{
                'label': DashboardSnapshotService._shortDateLabel(entry.key),
                'value': entry.value,
              })
          .toList(growable: false),
      'salesLast30Days': sales30.entries
          .map((entry) => <String, Object?>{
                'label': DashboardSnapshotService._shortDateLabel(entry.key),
                'value': entry.value,
              })
          .toList(growable: false),
      'expenseCategories': expenseList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'topProducts': topProductList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'topCustomers': topCustomerList
          .map((entry) => <String, Object?>{
                'label': entry.key,
                'value': entry.value,
              })
          .toList(growable: false),
      'recentOperations': recentOps.take(5).toList(growable: false),
      'recentStockMovements':
          recentStockMovements.take(8).toList(growable: false),
      'totalPurchasesAmount': totalPurchasesAmount,
      'totalExpensesAmount': totalExpensesAmount,
      'inventoryCostValue': inventoryCostValue,
      'lowStockCount': lowStockCount,
      'lowStockNames': lowStockNames,
      'todayExpenseTotal': todayExpenseTotal,
      'last7ExpenseAverage': DashboardSnapshotService._averageForWindow(expenseDailyTotals, start7, 7),
      'pendingSyncCount': pendingSyncCount,
      'blockingConflictCount': duplicateCodeCount + duplicateBarcodeCount,
    };
  }
}
