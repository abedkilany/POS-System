import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/data/app_store.dart').readAsStringSync();

  String methodBody(String signature, String nextSignature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: 'Missing $signature');
    final end = source.indexOf(nextSignature, start + signature.length);
    expect(end, isNonNegative, reason: 'Missing boundary $nextSignature');
    return source.substring(start, end);
  }

  test('purchase create commits invoice accounting and supplier ledger in SQLite transaction', () {
    final body = methodBody('Future<Purchase> createPurchase(', 'Future<Purchase> updatePurchaseDraft(');
    expect(body, contains("await sqliteDb.transaction(() async {"));
    expect(body, contains('await AccountingService.recordPurchase('));
    expect(body, contains("id: '\${purchase.id}-purchase-invoice'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });

  test('purchase return/cancel commit accounting reversal and supplier ledger with document', () {
    final returned = methodBody('Future<void> returnPurchase(', 'Future<void> cancelPurchase(');
    expect(returned, contains('notifyChange: false'));
    expect(returned, contains("id: '\${purchase.id}-purchase-return'"));
    expect(returned, contains('_persistAccountTransactionInExistingTransaction('));

    final cancelled = methodBody('Future<void> cancelPurchase(', 'Future<SaleQuotation> createSaleQuotation(');
    expect(cancelled, contains('await AccountingService.reverseEntryForReference('));
    expect(cancelled, contains("id: '\${purchase.id}-purchase-cancel'"));
    expect(cancelled, contains('_persistAccountTransactionInExistingTransaction('));
  });

  test('sale create commits invoice accounting and customer ledger with stock/document', () {
    final body = methodBody('Future<Sale> createSale(', 'Future<Sale> editSale(');
    expect(body, contains('await AccountingService.recordSale('));
    expect(body, contains("id: '\${sale.id}-sale-invoice'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
    expect(body, isNot(contains("_scheduleSaleAccounting(sale);")));
  });

  test('sale return commits credit note, accounting and customer ledger transactionally', () {
    final body = methodBody('Future<CreditNote> returnSale(', 'Future<void> cancelSale(');
    expect(body, contains('await BusinessSqliteStore.saveKeyJson('));
    expect(body, contains('await AccountingService.recordSaleReturn('));
    expect(body, contains("id: '\${sale.id}-sale-return-\${preparedCreditNote.id}'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });

  test('sale cancel commits accounting reversal and customer ledger with cancelled sale', () {
    final body = methodBody('Future<void> cancelSale(', '@Deprecated(');
    expect(body, contains('await AccountingService.reverseEntryForReference('));
    expect(body, contains("id: '\${sale.id}-sale-cancel'"));
    expect(body, contains('_persistAccountTransactionInExistingTransaction('));
  });
}
