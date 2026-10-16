import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';
import 'helpers/dart_library_source.dart';

void main() {
  final source = readAppStoreImplementationSource();

  String methodBody(String signature) =>
      extractDartMethodSource(source, signature);

  test(
      'purchase create commits invoice accounting and supplier ledger in SQLite transaction',
      () {
    final body = methodBody('Future<Purchase> createPurchase(');
    expect(body, contains("await sqliteDb.transaction(() async {"));
    expect(body, contains('await AccountingService.recordPurchase('));
    expect(body, contains("id: '\${purchase.id}-purchase-invoice'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });

  test(
      'purchase return/cancel commit accounting reversal and supplier ledger with document',
      () {
    final returned = methodBody('Future<void> returnPurchase(');
    expect(returned, contains('notifyChange: false'));
    expect(returned,
        contains('await AccountingService.reversePurchaseEntriesForPurchase('));
    expect(returned, contains("id: '\${purchase.id}-purchase-return'"));
    expect(
        returned, contains('_persistAccountTransactionInExistingTransaction('));

    final cancelled = methodBody('Future<void> cancelPurchase(');
    expect(cancelled,
        contains('await AccountingService.reversePurchaseEntriesForPurchase('));
    expect(cancelled, contains("id: '\${purchase.id}-purchase-cancel'"));
    expect(cancelled,
        contains('_persistAccountTransactionInExistingTransaction('));
  });

  test(
      'sale create commits invoice accounting and customer ledger with stock/document',
      () {
    final body = methodBody('Future<Sale> createSale(');
    expect(body, contains('await SalePostingService('));
    final posting =
        File('lib/core/services/sale_posting_service.dart').readAsStringSync();
    final transaction =
        extractDartBlockAfter(posting, 'await sqliteDb.transaction(');
    expect(transaction, contains('await postAccounting(sale)'));
    expect(transaction, contains("id: '\${sale.id}-sale-invoice'"));
    expect(transaction, contains('await _persistCustomerLedger('));
    expect(transaction,
        contains('await stockService.recordMovementsInTransaction('));
    expect(body, isNot(contains("_scheduleSaleAccounting(sale);")));
  });

  test(
      'sale return commits credit note, accounting and customer ledger transactionally',
      () {
    final body = methodBody('Future<CreditNote> returnSale(');
    expect(body, contains('await BusinessSqliteStore.saveKeyJson('));
    expect(body, contains('await AccountingService.recordSaleReturn('));
    expect(body,
        contains("id: '\${sale.id}-sale-return-\${preparedCreditNote.id}'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });

  test(
      'sale cancel commits accounting reversal and customer ledger with cancelled sale',
      () {
    final body = methodBody('Future<void> cancelSale(');
    expect(
        body, contains('await AccountingService.reverseSaleEntriesForSale('));
    expect(body, contains('includeSaleEditFamily: true'));
    expect(body, contains("id: '\${sale.id}-sale-cancel'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });
}
