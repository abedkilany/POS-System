import 'dart:convert';
import 'dart:async';

import '../../core/services/local_database_service.dart';
import '../../core/services/startup_timing_service.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';

class AccountingSnapshotService {
  const AccountingSnapshotService();

  static const String _cacheKeyPrefix = 'accounting_metrics_summary_v1';
  static final Map<String, Future<Map<String, Object?>>> _summaryFutures =
      <String, Future<Map<String, Object?>>>{};
  static final Map<String, Map<String, Object?>> _summaryCache =
      <String, Map<String, Object?>>{};

  String _cacheKey(AppStore store, DateTime reference) =>
      '${store.appIdentity.storeId}:${store.accountingRevision}:${reference.year}-${reference.month}-${reference.day}';

  String _sqliteCacheKey(AppStore store, DateTime reference) =>
      '$_cacheKeyPrefix:${store.appIdentity.storeId}:${store.accountingRevision}:${reference.year}-${reference.month}-${reference.day}';

  Map<String, Object?>? peekMetrics(AppStore store, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toLocal();
    final memoryCached = _summaryCache[_cacheKey(store, reference)];
    if (memoryCached != null) return memoryCached;
    final sqliteCached = _loadCachedMetrics(store, reference);
    if (sqliteCached != null) {
      _summaryCache[_cacheKey(store, reference)] = sqliteCached;
    }
    return sqliteCached;
  }

  Future<Map<String, Object?>> metricsFor(
    AppStore store, {
    DateTime? now,
  }) {
    final reference = (now ?? DateTime.now()).toLocal();
    final key = _cacheKey(store, reference);
    final cached = _summaryCache[key];
    if (cached != null) return Future.value(cached);
    final existing = _summaryFutures[key];
    if (existing != null) return existing;
    final future = _computeAndCacheMetrics(store, reference);
    _summaryFutures[key] = future;
    future.whenComplete(() {
      if (_summaryFutures[key] == future) {
        _summaryFutures.remove(key);
      }
    });
    return future;
  }

  Future<void> prewarm(AppStore store, {DateTime? now}) async {
    await metricsFor(store, now: now);
  }

  Future<Map<String, Object?>> _computeAndCacheMetrics(
    AppStore store,
    DateTime reference,
  ) async {
    final memoryCached = _summaryCache[_cacheKey(store, reference)];
    if (memoryCached != null) return memoryCached;

    final sqliteCached = _loadCachedMetrics(store, reference);
    if (sqliteCached != null) {
      _summaryCache[_cacheKey(store, reference)] = sqliteCached;
      return sqliteCached;
    }

    if (LocalDatabaseService.canQueryBusinessSqlite) {
      try {
        final sqliteMetrics = await StartupTimingService.measure(
          'accounting.snapshot_sql_metrics',
          () => LocalDatabaseService.buildAccountingMetricsFromSqlite(
            reference: reference,
          ),
          category: 'accounting',
        );
        if (sqliteMetrics != null) {
          _summaryCache[_cacheKey(store, reference)] = sqliteMetrics;
          unawaited(_saveCachedMetrics(store, reference, sqliteMetrics));
          return sqliteMetrics;
        }
      } catch (_) {
        // Keep accounting DB-first; the in-memory store is only a safety net
        // when typed SQL is unavailable or fails.
      }
    }
    final computed = await StartupTimingService.measure(
      'accounting.snapshot_store_metrics',
      () async => _computeSnapshotFromStore(store, reference),
      category: 'accounting',
    );
    _summaryCache[_cacheKey(store, reference)] = computed;
    return computed;
  }

  Map<String, Object?>? _loadCachedMetrics(AppStore store, DateTime reference) {
    final cached =
        LocalDatabaseService.getString(_sqliteCacheKey(store, reference));
    if (cached == null || cached.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map) return null;
      return <String, Object?>{
        for (final entry in decoded.entries)
          entry.key.toString():
              entry.value is num ? entry.value : entry.value?.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedMetrics(
    AppStore store,
    DateTime reference,
    Map<String, Object?> metrics,
  ) async {
    try {
      await LocalDatabaseService.setString(
        _sqliteCacheKey(store, reference),
        jsonEncode(metrics),
      );
    } catch (_) {
      // Cache persistence is best-effort only.
    }
  }
}

Map<String, Object?> _computeSnapshotFromStore(
  AppStore store,
  DateTime reference,
) {
  final today = DateTime(reference.year, reference.month, reference.day);
  final transactions = store.accountTransactions;

  final accountBalances = <String, double>{};
  var customerReceivables = 0.0;
  var customerCredits = 0.0;
  var supplierPayables = 0.0;
  var supplierAdvances = 0.0;
  var todayCashIn = 0.0;
  var todayCashOut = 0.0;

  for (final txn in transactions) {
    if (txn.isDeleted) continue;
    final type = txn.accountType.trim().toLowerCase();
    final accountId = txn.accountId.trim();
    if (accountId.isEmpty) continue;
    if (type != 'customer' && type != 'supplier') continue;

    final key = '$type|$accountId';
    accountBalances[key] = (accountBalances[key] ?? 0) + txn.signedAmount;

    final date = txn.date.toLocal();
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      if (_isCashIn(txn)) {
        todayCashIn += _cashAmount(txn);
      }
      if (_isCashOut(txn)) {
        todayCashOut += _cashAmount(txn);
      }
    }
  }

  for (final entry in accountBalances.entries) {
    if (entry.key.startsWith('customer|')) {
      if (entry.value > 0) {
        customerReceivables += entry.value;
      } else if (entry.value < 0) {
        customerCredits += entry.value.abs();
      }
      continue;
    }
    if (entry.value < 0) {
      supplierPayables += entry.value.abs();
    } else if (entry.value > 0) {
      supplierAdvances += entry.value;
    }
  }

  return <String, Object?>{
    'reference': reference.toIso8601String(),
    'customerReceivables': customerReceivables,
    'customerCredits': customerCredits,
    'supplierPayables': supplierPayables,
    'supplierAdvances': supplierAdvances,
    'todayCashIn': todayCashIn,
    'todayCashOut': todayCashOut,
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
