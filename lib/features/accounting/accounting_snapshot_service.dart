import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/services/local_database_service.dart';
import '../../core/services/startup_timing_service.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';

class AccountingSnapshotService {
  const AccountingSnapshotService();

  static final Map<String, Future<Map<String, Object?>>> _summaryFutures =
      <String, Future<Map<String, Object?>>>{};
  static final Map<String, Map<String, Object?>> _summaryCache =
      <String, Map<String, Object?>>{};

  String _cacheKey(AppStore store, DateTime reference) =>
      '${store.appIdentity.storeId}:${store.accountingRevision}:${reference.year}-${reference.month}-${reference.day}';

  Map<String, Object?>? peekMetrics(AppStore store, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toLocal();
    return _summaryCache[_cacheKey(store, reference)];
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
          return sqliteMetrics;
        }
      } catch (_) {
        // Fall back to the legacy snapshot path if SQLite metrics generation fails.
      }
    }
    final raw = await StartupTimingService.measure(
      'accounting.snapshot_raw_load',
      _loadRawData,
      category: 'accounting',
    );
    final computed = await compute<Map<String, Object?>, Map<String, Object?>>(
      _computeSnapshot,
      raw.toComputeInput(reference),
    );
    _summaryCache[_cacheKey(store, reference)] = computed;
    return computed;
  }

  Future<_RawAccountingData> _loadRawData() async {
    final raw = await LocalDatabaseService.getBusinessEntityListJson(
      'account_transactions_v1',
    );
    return _RawAccountingData(accountTransactionsJson: raw ?? '[]');
  }
}

Map<String, Object?> _computeSnapshot(Map<String, Object?> input) {
  final reference = DateTime.parse(input['reference'].toString()).toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final transactions = _decodeList(
    input['accountTransactionsJson'].toString(),
    AccountTransaction.fromJson,
  );

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

List<T> _decodeList<T>(
  String raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw.trim().isEmpty) return <T>[];
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded
      .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);
}

bool _isCashIn(AccountTransaction txn) =>
    txn.type == 'paymentReceived' ||
    (txn.type == 'paymentReversal' && txn.accountType == 'supplier');

bool _isCashOut(AccountTransaction txn) =>
    txn.type == 'paymentPaid' ||
    (txn.type == 'paymentReversal' && txn.accountType == 'customer');

double _cashAmount(AccountTransaction txn) =>
    txn.debit > 0 ? txn.debit : txn.credit;

class _RawAccountingData {
  const _RawAccountingData({
    required this.accountTransactionsJson,
  });

  final String accountTransactionsJson;

  Map<String, Object?> toComputeInput(DateTime reference) {
    return <String, Object?>{
      'reference': reference.toIso8601String(),
      'accountTransactionsJson': accountTransactionsJson,
    };
  }
}
