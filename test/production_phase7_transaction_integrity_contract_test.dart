import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('production sqlite commits use FULL durability', () {
    final source = read('lib/core/storage/sqlite/ventio_drift_database.dart');
    expect(source, contains('PRAGMA journal_mode = WAL;'));
    expect(source, contains('PRAGMA synchronous = FULL;'));
    expect(source, contains('PRAGMA busy_timeout = 5000;'));
    expect(source, isNot(contains('PRAGMA synchronous = NORMAL;')));
  });

  test('journal posting owns duplicate check and persistence post-condition', () {
    final source = read('lib/core/services/accounting_service.dart');
    final start = source.indexOf('static Future<String> createPostedEntry(');
    final end = source.indexOf(
      'static Future<int> countPostedJournalEntriesForReferences(',
      start,
    );
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    final persistStart = body.indexOf('Future<bool> persistEntry() async {');
    expect(persistStart, isNonNegative);
    final persist = body.substring(persistStart);
    expect(persist, contains('_hasActiveEntryForReference('));
    expect(persist, contains('final entryNo = await _nextEntryNo('));
    expect(persist, contains('COUNT(jl.id) AS line_count'));
    expect(persist, contains('COALESCE(SUM(jl.debit), 0) AS total_debit'));
    expect(persist, contains('COALESCE(SUM(jl.credit), 0) AS total_credit'));
    expect(persist, contains('lineCount != draft.lines.length'));
    expect(persist, contains("persisted.data['status']?.toString() != 'posted'"));
  });

  test('account transaction row and accounting effects share one transaction', () {
    final source = read('lib/data/app_store_persistence_sync_core.dart');
    final addStart = source.indexOf('Future<void> addOrUpdateAccountTransaction(');
    final addEnd = source.indexOf('Future<void> deleteAccountTransaction(', addStart);
    final add = source.substring(addStart, addEnd);
    expect(add, contains('await sqliteDb.transaction(() async {'));
    expect(add, contains('await _persistAccountTransactionInExistingTransaction('));
    expect(add, contains('await AccountingService.recordAccountPayment('));
    expect(add, contains('withinExistingTransaction: true'));
    expect(add, contains('Account payment edited'));

    final deleteStart = addEnd;
    final deleteEnd = source.indexOf(
      'Future<void> _upsertAccountTransactionInternal(',
      deleteStart,
    );
    final delete = source.substring(deleteStart, deleteEnd);
    expect(delete, contains('await sqliteDb.transaction(() async {'));
    expect(delete, contains('await AccountingService.reverseEntryForReference('));
    expect(delete, contains('await _persistAccountTransactionInExistingTransaction('));
  });

  test('standalone account payment owns journal and cash transaction', () {
    final source = read('lib/core/services/accounting_service.dart');
    final start = source.indexOf('static Future<void> recordAccountPayment(');
    final end = source.indexOf('static Future<String> createPostedEntry(', start);
    final body = source.substring(start, end);
    expect(body, contains('bool withinExistingTransaction = false'));
    expect(body, contains('await db.transaction(persistPayment)'));
    expect(body, contains('withinExistingTransaction: true'));
    expect(body, contains('database: db'));
  });

  test('stock operation completion is inside the movement transaction', () {
    final source = read('lib/core/services/stock_transaction_service.dart');
    final start = source.indexOf('Future<StockTransactionReceipt> recordMovementsAtomically(');
    final end = source.indexOf('Future<StockTransactionReceipt> recordMovementsInTransaction(', start);
    final body = source.substring(start, end);
    final tx = body.indexOf('await db.transaction(() async {');
    final movement = body.indexOf('receipt = await recordMovementsInTransaction(', tx);
    final completed = body.indexOf('await _markOperationCompleted(', movement);
    expect(tx, isNonNegative);
    expect(movement, greaterThan(tx));
    expect(completed, greaterThan(movement));
  });

  test('fixed asset and depreciation artifacts are transaction-owned', () {
    final source = read('lib/core/services/accounting_service.dart');
    final assetStart = source.indexOf('static Future<void> createFixedAsset({');
    final assetEnd = source.indexOf('static Future<int> runDepreciationForAsset(', assetStart);
    final asset = source.substring(assetStart, assetEnd);
    expect(asset, contains('await _db.transaction(() async {'));
    expect(asset, contains('INSERT INTO fixed_assets'));
    expect(asset, contains('withinExistingTransaction: true'));
    expect(asset, contains('Fixed asset journal entry was not persisted.'));
    expect(asset, contains('_writeAuditLogInTransaction('));

    final depStart = source.indexOf('static Future<int> _runDepreciationForAssetRow(');
    final depEnd = source.indexOf('static Future<void> createManualJournalEntry(', depStart);
    final dep = source.substring(depStart, depEnd);
    expect(dep, contains('final inserted = await _db.transaction(() async {'));
    expect(dep, contains('FROM fixed_asset_depreciation'));
    expect(dep, contains('INSERT INTO fixed_asset_depreciation'));
    expect(dep, isNot(contains('INSERT OR IGNORE INTO fixed_asset_depreciation')));
  });
}
