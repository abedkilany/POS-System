import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account transaction writers are SQLite-first and awaited', () {
    final source = File('lib/data/app_store.dart').readAsStringSync();

    final persistStart = source.indexOf(
      'Future<void> _persistAccountTransactionSqliteFirst(',
    );
    final publicStart = source.indexOf(
      'Future<void> addOrUpdateAccountTransaction(',
      persistStart,
    );
    expect(persistStart, greaterThanOrEqualTo(0));
    expect(publicStart, greaterThan(persistStart));
    final persistenceHelper = source.substring(persistStart, publicStart);
    expect(
      persistenceHelper,
      contains('await LocalDatabaseService.upsertBusinessEntityJsons('),
    );

    final internalStart = source.indexOf(
      'Future<void> _upsertAccountTransactionInternal(',
      publicStart,
    );
    final internalEnd = source.indexOf(
      'Future<void> _recordPurchaseLedger(',
      internalStart,
    );
    expect(internalStart, greaterThan(publicStart));
    expect(internalEnd, greaterThan(internalStart));
    final writer = source.substring(internalStart, internalEnd);
    expect(
      writer,
      contains('await _persistAccountTransactionSqliteFirst(synced);'),
    );
    expect(
      writer.indexOf('await _persistAccountTransactionSqliteFirst(synced);'),
      lessThan(writer.indexOf('_putAccountTransactionAtIndex(')),
    );

    final directCalls = RegExp(
      r'(?<!await )_upsertAccountTransactionInternal\s*\(',
    ).allMatches(source.substring(internalEnd));
    expect(directCalls, isEmpty);
  });

  // Phase 9 contract: voucher-backed customer/supplier payments must not depend
  // on a second AppStore account-transaction write after the voucher commits.
  test('voucher payment compatibility ledger is owned by PaymentVoucherService transaction', () {
    final service = File('lib/core/services/payment_voucher_service.dart').readAsStringSync();
    final store = File('lib/data/app_store.dart').readAsStringSync();

    expect(service, contains('await _insertCompatibilityAccountMovement('));
    expect(service, contains('await _reverseCompatibilityAccountMovements('));
    expect(service, contains('await _insertCompatibilityRefundMovement('));

    final saleStart = store.indexOf('Future<Sale> _settleSalePaymentInternal({');
    final saleEnd = store.indexOf('Future<Purchase> settlePurchasePayment({', saleStart);
    final salePath = store.substring(saleStart, saleEnd);
    expect(salePath, contains('await PaymentVoucherService(sqliteDb).createReceipt('));
    expect(salePath, contains('await refreshAccountTransactionsFromSqlite();'));
    expect(salePath, isNot(contains('_upsertAccountTransactionInternal(')));

    final purchaseStart = saleEnd;
    final purchaseEnd = store.indexOf('Future<Purchase> createPurchase({', purchaseStart);
    final purchasePath = store.substring(purchaseStart, purchaseEnd);
    expect(purchasePath, contains('await PaymentVoucherService(sqliteDb).createPayment('));
    expect(purchasePath, contains('await refreshAccountTransactionsFromSqlite();'));
    expect(purchasePath, isNot(contains('_upsertAccountTransactionInternal(')));
  });
}
