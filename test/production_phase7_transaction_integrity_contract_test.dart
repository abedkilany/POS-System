import 'package:flutter_test/flutter_test.dart';

import 'helpers/accounting_service_source.dart';
import 'helpers/dart_library_source.dart';

void main() {
  String read(String path) =>
      path == 'lib/core/services/accounting_service.dart'
          ? readAccountingServiceImplementationSource()
          : readDartLibrarySource(path);

  test('production sqlite commits use FULL durability', () {
    final source = read('lib/core/storage/sqlite/ventio_drift_database.dart');
    expect(source, contains('PRAGMA journal_mode = WAL;'));
    expect(source, contains('PRAGMA synchronous = FULL;'));
    expect(source, contains('PRAGMA busy_timeout = 5000;'));
    expect(source, isNot(contains('PRAGMA synchronous = NORMAL;')));
  });

  test('journal posting owns duplicate check and persistence post-condition',
      () {
    final source = read('lib/core/services/accounting_service.dart');
    final start = source.indexOf('Future<String> createPostedEntry(');
    final end = source.indexOf(
      'Future<int> countPostedJournalEntriesForReferences(',
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
    expect(
        persist, contains("persisted.data['status']?.toString() != 'posted'"));
  });

  test('account transaction row and accounting effects share one transaction',
      () {
    final purchaseSource =
        readDartLibrarySource('lib/data/app_store_purchases_split_07.dart');
    final cancellation = extractDartMethodSource(
      purchaseSource,
      'Future<void> cancelPurchase(',
    );
    final transaction = extractDartBlockAfter(
      cancellation,
      'await sqliteDb.transaction(() async {',
    );

    expect(
      transaction,
      contains('await AccountingService.reversePurchaseEntriesForPurchase('),
    );
    expect(transaction, contains('withinExistingTransaction: true'));
    expect(
      transaction,
      contains('await _persistAccountTransactionInExistingTransaction('),
    );
    expect(transaction, contains("id: '\${purchase.id}-purchase-cancel'"));
  });

  test('standalone account payment owns journal and cash transaction', () {
    final source = read('lib/core/services/accounting_service.dart');
    final start = source.indexOf('Future<void> recordAccountPayment(');
    final end = source.indexOf('Future<String> createPostedEntry(', start);
    final body = source.substring(start, end);
    expect(body, contains('bool withinExistingTransaction = false'));
    expect(body, contains('await db.transaction(persistPayment)'));
    expect(body, contains('withinExistingTransaction: true'));
    expect(body, contains('database: db'));
  });

  test('stock operation completion is inside the movement transaction', () {
    final source = read('lib/core/services/stock_transaction_service.dart');
    final start = source
        .indexOf('Future<StockTransactionReceipt> recordMovementsAtomically(');
    final end = source.indexOf(
        'Future<StockTransactionReceipt> recordMovementsInTransaction(', start);
    final body = source.substring(start, end);
    final tx = body.indexOf('await db.transaction(() async {');
    final movement =
        body.indexOf('receipt = await recordMovementsInTransaction(', tx);
    final completed = body.indexOf('await _markOperationCompleted(', movement);
    expect(tx, isNonNegative);
    expect(movement, greaterThan(tx));
    expect(completed, greaterThan(movement));
  });

  test('fixed asset and depreciation artifacts are transaction-owned', () {
    final source = read('lib/core/services/accounting_service.dart');
    final assetStart = source.indexOf('Future<void> createFixedAsset({');
    final assetEnd =
        source.indexOf('Future<int> runDepreciationForAsset(', assetStart);
    final asset = source.substring(assetStart, assetEnd);
    expect(asset, contains('await _db.transaction(() async {'));
    expect(asset, contains('INSERT INTO fixed_assets'));
    expect(asset, contains('withinExistingTransaction: true'));
    expect(asset, contains('Fixed asset journal entry was not persisted.'));
    expect(asset, contains('_writeAuditLogInTransaction('));

    final depStart = source.indexOf('Future<int> _runDepreciationForAssetRow(');
    final depEnd =
        source.indexOf('Future<void> createManualJournalEntry(', depStart);
    final dep = source.substring(depStart, depEnd);
    expect(dep, contains('final inserted = await _db.transaction(() async {'));
    expect(dep, contains('FROM fixed_asset_depreciation'));
    expect(dep, contains('INSERT INTO fixed_asset_depreciation'));
    expect(
        dep, isNot(contains('INSERT OR IGNORE INTO fixed_asset_depreciation')));
  });
}
