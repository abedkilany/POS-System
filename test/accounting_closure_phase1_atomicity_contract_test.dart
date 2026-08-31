import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  final source = readAppStoreImplementationSource();

  String methodBody(String signature, String nextSignature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: 'Missing $signature');
    final end = source.indexOf(nextSignature, start + signature.length);
    expect(end, isNonNegative, reason: 'Missing boundary $nextSignature');
    return source.substring(start, end);
  }

  test('sale FIFO consumption is owned by the SQLite sale transaction', () {
    final helperStart = source.indexOf(
      'Future<InventoryCostResult> _resolveCostForSaleItemInTransaction(',
    );
    final helperEnd = source.indexOf(
      'Future<void> _restoreInventoryCostLayersFromSaleItemsInTransaction(',
      helperStart,
    );
    expect(helperStart, isNonNegative);
    expect(helperEnd, greaterThan(helperStart));
    final helper = source.substring(helperStart, helperEnd);
    expect(helper, contains('BusinessSqliteStore.readInventoryCostLayers(db)'));
    expect(helper, contains('UPDATE inventory_cost_layers'));
    expect(helper, contains('SET quantity_remaining = ?'));
    expect(helper, contains('ABS(quantity_remaining - ?) <= 0.000001'));
    expect(helper, contains('SELECT quantity_remaining'));
    expect(helper, contains('consumption was not persisted atomically'));

    final sale = methodBody(
      'Future<Sale> createSale(',
      'Future<Map<String, double>> _returnedSaleQuantitiesByProduct(',
    );
    final transactionStart = sale.indexOf('await sqliteDb.transaction(() async {');
    final transactionEnd = sale.indexOf('});', transactionStart);
    expect(transactionStart, isNonNegative);
    expect(transactionEnd, greaterThan(transactionStart));
    final transaction = sale.substring(transactionStart, transactionEnd);
    expect(
      transaction,
      contains('await _resolveCostForSaleItemInTransaction('),
    );
    expect(transaction, contains('await AccountingService.recordSale('));
    expect(sale, contains('await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);'));
    expect(sale, contains('productDerivedData: false'));
  });

  test('sale return and cancel restore FIFO layers inside their transactions', () {
    final returned = methodBody(
      'Future<CreditNote> returnSale(',
      'Future<void> cancelSale(',
    );
    expect(
      returned,
      contains('await _restoreInventoryCostLayersFromSaleItemsInTransaction('),
    );
    expect(returned, contains('await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);'));
    expect(returned, contains('final productDerivedData = !authoritativeSqlite'));

    final cancelled = methodBody('Future<void> cancelSale(', 'Future<void> deleteSale(');
    expect(
      cancelled,
      contains('await _restoreInventoryCostLayersFromSaleItemsInTransaction('),
    );
    expect(cancelled, contains('await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);'));
    expect(cancelled, contains('productDerivedData: !saleCancelWasAtomic'));
  });

  test('purchase return and cancel close layers transactionally and block consumed layers', () {
    final helperStart = source.indexOf(
      'Future<void> _closeInventoryCostLayersForPurchaseInTransaction(',
    );
    final helperEnd = source.indexOf(
      'Future<_ManufacturingCostResolution> _consumeManufacturingCostInTransaction(',
      helperStart,
    );
    expect(helperStart, isNonNegative);
    expect(helperEnd, greaterThan(helperStart));
    final helper = source.substring(helperStart, helperEnd);
    expect(helper, contains('layer.quantityRemaining + 0.000001 < layer.quantityReceived'));
    // Purchase reversal now closes authoritative FIFO rows directly in the same
    // SQLite transaction, then reads the table back and blocks commit if any
    // residual quantity remains. Do not require the old generic upsert path.
    expect(helper, contains('UPDATE inventory_cost_layers'));
    expect(helper, contains('SET quantity_remaining = 0'));
    expect(helper, contains('WHERE purchase_id = ?'));
    expect(helper, contains('SELECT COALESCE(SUM(quantity_remaining), 0) AS qty'));
    expect(helper, contains('cost layers did not close atomically'));

    final returned = methodBody(
      'Future<void> returnPurchase(',
      'Future<void> cancelPurchase(',
    );
    expect(
      returned,
      contains('await _closeInventoryCostLayersForPurchaseInTransaction('),
    );
    expect(returned, contains('await _activePurchaseReceiveMovements('));
    expect(returned, contains('await batchService.adjustUnifiedBatchInTransaction('));
    expect(returned, contains('productDerivedData: false'));
    expect(returned, contains('await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);'));
    expect(returned, contains('await refreshAfterDatabaseChange(AppStore._stockMovementsKey);'));
    expect(returned, contains('await refreshAccountTransactionsFromSqlite();'));

    final cancelled = methodBody(
      'Future<void> cancelPurchase(',
      'Future<InventoryCountSession> createInventoryCountSession(',
    );
    expect(
      cancelled,
      contains('await _closeInventoryCostLayersForPurchaseInTransaction('),
    );
    expect(cancelled, contains('await _activePurchaseReceiveMovements('));
    expect(cancelled, contains('await batchService.adjustUnifiedBatchInTransaction('));
    expect(cancelled, contains('productDerivedData: false'));
    expect(cancelled, contains('await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);'));
    expect(cancelled, contains('await refreshAfterDatabaseChange(AppStore._stockMovementsKey);'));
    expect(cancelled, contains('await refreshAccountTransactionsFromSqlite();'));
  });

  test('financial transactions verify the persisted journal before commit', () {
    expect(source, contains('Future<void> _requirePostedJournalInTransaction('));
    expect(source, contains('Future<void> _requireNoActiveJournalInTransaction('));

    final sale = methodBody(
      'Future<Sale> createSale(',
      'Future<Map<String, double>> _returnedSaleQuantitiesByProduct(',
    );
    expect(sale, contains("referenceType: 'sale'"));
    expect(sale, contains('Sale journal was not persisted'));

    final returned = methodBody(
      'Future<CreditNote> returnSale(',
      'Future<void> cancelSale(',
    );
    expect(returned, contains('returnJournalId'));
    expect(returned, contains('Sale return journal is missing'));

    final cancelled = methodBody('Future<void> cancelSale(', 'Future<void> deleteSale(');
    expect(cancelled, contains('Active sale journal is missing'));
    expect(cancelled, contains('Sale journal reversal did not complete'));
    expect(cancelled, contains('Cannot cancel a sale after a return has been posted'));
  });

  test('draft receive posts purchase accounting before SQLite commit', () {
    final receive = methodBody(
      'Future<void> receivePurchase(',
      'Future<void> permanentlyDeleteCancelledPurchase(',
    );
    final authoritativeStart = receive.indexOf(
      'if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {',
    );
    final fallbackStart = receive.indexOf(
      'final now = DateTime.now();',
      receive.indexOf('return;', authoritativeStart) + 1,
    );
    expect(authoritativeStart, isNonNegative);
    expect(fallbackStart, greaterThan(authoritativeStart));
    final authoritative = receive.substring(authoritativeStart, fallbackStart);
    expect(authoritative, contains('await sqliteDb.transaction(() async {'));
    expect(authoritative, contains('final accountingPosted = await AccountingService.recordPurchase('));
    expect(authoritative, contains('withinExistingTransaction: true'));
    expect(authoritative, contains('if (!accountingPosted)'));
    expect(authoritative, contains('await _requirePostedJournalInTransaction('));
    expect(authoritative, contains('purchase receipt was rolled back'));
    expect(authoritative, contains("id: '\${received.id}-purchase-invoice'"));
    expect(authoritative, isNot(contains('_schedulePurchaseAccounting(received)')));
  });
}
