import 'dart:async';

import '../../core/services/local_database_service.dart';
import '../../core/services/startup_timing_service.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../../models/sale.dart';

class ReportsSnapshotService {
  const ReportsSnapshotService();

  static final Map<String, Future<Map<String, Object?>>> _summaryFutures =
      <String, Future<Map<String, Object?>>>{};
  static final Map<String, Map<String, Object?>> _summaryCache =
      <String, Map<String, Object?>>{};

  String _cacheKey(AppStore store, DateTime reference) =>
      '${store.appIdentity.storeId}:${store.reportsRevision}:${reference.year}-${reference.month}-${reference.day}';

  Map<String, Object?>? peekSummary(AppStore store, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toLocal();
    return _summaryCache[_cacheKey(store, reference)];
  }

  Future<Map<String, Object?>> summaryFor(
    AppStore store, {
    DateTime? now,
  }) {
    final reference = (now ?? DateTime.now()).toLocal();
    final key = _cacheKey(store, reference);
    final cached = _summaryCache[key];
    if (cached != null) return Future.value(cached);
    final existing = _summaryFutures[key];
    if (existing != null) return existing;
    final future = _computeAndCacheSummary(store, reference);
    _summaryFutures[key] = future;
    future.whenComplete(() {
      if (_summaryFutures[key] == future) {
        _summaryFutures.remove(key);
      }
    });
    return future;
  }

  Future<void> prewarm(AppStore store, {DateTime? now}) async {
    await summaryFor(store, now: now);
  }

  Future<Map<String, Object?>> _computeAndCacheSummary(
    AppStore store,
    DateTime reference,
  ) async {
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      try {
        final sqliteSummary = await StartupTimingService.measure(
          'reports.snapshot_sql_summary',
          () => LocalDatabaseService.buildReportsSummaryFromSqlite(
            reference: reference,
          ),
          category: 'reports',
        );
        if (sqliteSummary != null) {
          _summaryCache[_cacheKey(store, reference)] = sqliteSummary;
          return sqliteSummary;
        }
      } catch (_) {
        // Keep reports DB-first; the in-memory store is only a safety net when
        // typed SQL is unavailable or fails.
      }
    }
    final computed = await StartupTimingService.measure(
      'reports.snapshot_store_summary',
      () async => _computeSnapshotFromStore(store, reference),
      category: 'reports',
    );
    _summaryCache[_cacheKey(store, reference)] = computed;
    return computed;
  }
}

Map<String, Object?> _computeSnapshotFromStore(
  AppStore store,
  DateTime reference,
) {
  final today = DateTime(reference.year, reference.month, reference.day);
  final products = store.products;
  final sales = store.sales;
  final purchases = store.purchases;
  final expenses = store.expenses;
  final stockMovements = store.stockMovements;
  final accountTransactions = store.accountTransactions;
  final customers = store.customers;
  final suppliers = store.suppliers;

  var totalExpensesAmount = 0.0;
  var estimatedProfit = 0.0;
  var todaySales = 0.0;
  var monthSales = 0.0;
  var monthPurchases = 0.0;
  var movementIn = 0.0;
  var movementOut = 0.0;
  var inventoryRetailValue = 0.0;
  final lowStock = <Map<String, Object?>>[];
  final stockMovementRows = <Map<String, Object?>>[];
  final autoCorrections = <Map<String, Object?>>[];
  final topProducts = <String, double>{};
  final topCustomerBalances = <String, double>{};
  final topSupplierBalances = <String, double>{};
  final accountBalances = <String, double>{};
  final todayCashInByMethod = <String, double>{};
  final todayCashOutByMethod = <String, double>{};
  var customerReceivables = 0.0;
  var supplierPayables = 0.0;
  var todayCashIn = 0.0;
  var todayCashOut = 0.0;

  final activeSales = <Sale>[];
  for (final sale in sales) {
    if (sale.isDeleted || sale.isCancelled) continue;
    activeSales.add(sale);
    final date = sale.date.toLocal();
    if (date.year == today.year && date.month == today.month) {
      monthSales += sale.total;
      if (date.day == today.day) {
        todaySales += sale.total;
      }
    }
  }
  for (final sale in activeSales) {
    for (final item in sale.items) {
      final name = item.productName.trim();
      if (name.isEmpty) continue;
      topProducts[name] = (topProducts[name] ?? 0) + item.quantity;
    }
  }

  for (final purchase in purchases) {
    if (purchase.isDeleted || purchase.isCancelled) continue;
    monthPurchases += purchase.subtotal;
  }

  for (final expense in expenses) {
    if (expense.isDeleted || !expense.isPosted) continue;
    totalExpensesAmount += expense.amount;
  }

  for (final product in products) {
    if (product.isDeleted) continue;
    if (!product.trackStock) continue;
    inventoryRetailValue += product.usdPrice * product.stock;
    if (product.stock <= product.lowStockThreshold) {
      lowStock.add(<String, Object?>{
        'name': product.name,
        'code': product.code,
        'stock': product.stock,
      });
    }
  }

  for (final movement in stockMovements) {
    final date = movement.date.toLocal();
    if (movement.quantity > 0) movementIn += movement.quantity;
    if (movement.quantity < 0) movementOut += movement.quantity.abs();
    final row = <String, Object?>{
      'type': movement.type,
      'productName': movement.productName,
      'referenceNo': movement.referenceNo,
      'quantity': movement.quantity,
      'date': date.toIso8601String(),
    };
    stockMovementRows.add(row);
    if (movement.type == 'auto_correction') {
      autoCorrections.add(row);
    }
  }
  stockMovementRows.sort((a, b) {
    final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });
  autoCorrections.sort((a, b) {
    final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });

  for (final txn in accountTransactions) {
    if (txn.isDeleted) continue;
    final type = txn.accountType.trim().toLowerCase();
    final accountId = txn.accountId.trim();
    if (type != 'customer' && type != 'supplier') continue;
    if (accountId.isEmpty) continue;
    final key = '$type|$accountId';
    accountBalances[key] = (accountBalances[key] ?? 0) + txn.signedAmount;

    final date = txn.date.toLocal();
    final method = txn.paymentMethod.trim().isEmpty
        ? 'not_specified'
        : txn.paymentMethod.trim();
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      if (_isCashIn(txn)) {
        todayCashIn += _cashAmount(txn);
        todayCashInByMethod[method] =
            (todayCashInByMethod[method] ?? 0) + _cashAmount(txn);
      }
      if (_isCashOut(txn)) {
        todayCashOut += _cashAmount(txn);
        todayCashOutByMethod[method] =
            (todayCashOutByMethod[method] ?? 0) + _cashAmount(txn);
      }
    }
  }

  for (final customer in customers) {
    final balance = accountBalances['customer|${customer.id}'] ?? 0;
    if (balance > 0) {
      customerReceivables += balance;
      final name = customer.name.trim().isEmpty ? customer.id : customer.name;
      topCustomerBalances[name] = balance;
    }
  }
  for (final supplier in suppliers) {
    final balance = accountBalances['supplier|${supplier.id}'] ?? 0;
    if (balance < 0) {
      supplierPayables += balance.abs();
      final name = supplier.name.trim().isEmpty ? supplier.id : supplier.name;
      topSupplierBalances[name] = balance;
    }
  }

  estimatedProfit = activeSales.fold<double>(
        0,
        (sum, sale) => sum + sale.grossProfit,
      ) -
      totalExpensesAmount;

  final topProductLines = topProducts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topCustomerDebts = topCustomerBalances.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topSupplierDebts = topSupplierBalances.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  return <String, Object?>{
    'reference': reference.toIso8601String(),
    'totalExpenses': totalExpensesAmount,
    'estimatedProfit': estimatedProfit,
    'todaySales': todaySales,
    'monthSales': monthSales,
    'monthPurchases': monthPurchases,
    'movementIn': movementIn,
    'movementOut': movementOut,
    'autoCorrections': autoCorrections,
    'lowStock': lowStock,
    'stockMovements': stockMovementRows,
    'customerReceivables': customerReceivables,
    'supplierPayables': supplierPayables,
    'inventoryRetailValue': inventoryRetailValue,
    'lowStockCount': lowStock.length,
    'todayCashIn': todayCashIn,
    'todayCashOut': todayCashOut,
    'todayCashInByMethod': todayCashInByMethod,
    'todayCashOutByMethod': todayCashOutByMethod,
    'topProductLines': topProductLines
        .map((entry) => <String, Object?>{
              'key': entry.key,
              'value': entry.value,
            })
        .toList(growable: false),
    'topCustomerDebts': topCustomerDebts
        .map((entry) => <String, Object?>{
              'key': entry.key,
              'value': entry.value,
            })
        .toList(growable: false),
    'topSupplierDebts': topSupplierDebts
        .map((entry) => <String, Object?>{
              'key': entry.key,
              'value': entry.value,
            })
        .toList(growable: false),
  };
}

bool _isCashIn(AccountTransaction txn) =>
    txn.type == 'paymentReceived' ||
    (txn.type == 'paymentReversal' && txn.accountType == 'supplier');

bool _isCashOut(AccountTransaction txn) =>
    txn.type == 'paymentPaid' ||
    (txn.type == 'paymentReversal' && txn.accountType == 'customer');

double _cashAmount(AccountTransaction txn) =>
    txn.debit > 0 ? txn.debit : txn.credit;
