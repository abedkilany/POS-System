import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';
import 'helpers/dart_library_source.dart';

void main() {
  test('account transaction writers are SQLite-first and awaited', () {
    final persistenceSource = readDartLibrarySource(
      'lib/data/app_store_persistence_sync_core_split_04.dart',
    );
    final writerSource = readDartLibrarySource(
      'lib/data/app_store_persistence_sync_core_split_05.dart',
    );
    final persistenceHelper = extractDartMethodSource(
      persistenceSource,
      'Future<void> _persistAccountTransactionSqliteFirst(',
    );
    expect(
      persistenceHelper,
      contains('await LocalDatabaseService.upsertBusinessEntityJsons('),
    );
    expect(persistenceHelper, contains('finally {'));
    expect(persistenceHelper, contains('_sqliteDirtyBusinessRows'));

    final writer = extractDartMethodSource(
      writerSource,
      'Future<void> _upsertAccountTransactionInternal(',
    );
    expect(
      writer,
      contains('await _persistAccountTransactionSqliteFirst(synced);'),
    );
    expect(
      writer.indexOf('await _persistAccountTransactionSqliteFirst(synced);'),
      lessThan(writer.indexOf('_putAccountTransactionAtIndex(')),
    );

    final appStore = readAppStoreImplementationSource();
    final implementation = extractDartMethodSource(
      appStore,
      'Future<void> _upsertAccountTransactionInternal(',
    );
    final callSites = appStore.replaceFirst(implementation, '');
    final unawaitedWrites = RegExp(
      r'(?<!await )_upsertAccountTransactionInternal\s*\(',
    ).allMatches(callSites);
    expect(unawaitedWrites, isEmpty);
  });

  // Phase 9 contract: voucher-backed customer/supplier payments must not depend
  // on a second AppStore account-transaction write after the voucher commits.
  test(
      'voucher payment compatibility ledger is owned by PaymentVoucherService transaction',
      () {
    final service =
        readDartLibrarySource('lib/core/services/payment_voucher_service.dart');
    final store = readAppStoreImplementationSource();

    expect(service, contains('await _insertCompatibilityAccountMovement('));
    expect(service, contains('await _reverseCompatibilityAccountMovements('));
    expect(service, contains('await _insertCompatibilityRefundMovement('));

    final salePath = extractDartMethodSource(
      store,
      'Future<Sale> _settleSalePaymentInternal(',
    );
    expect(salePath,
        contains('await PaymentVoucherService(sqliteDb).createReceipt('));
    expect(
      salePath,
      contains('await _refreshAccountTransactionsFromSqlite();'),
    );
    expect(salePath, isNot(contains('_upsertAccountTransactionInternal(')));

    final purchasePath = extractDartMethodSource(
      store,
      'Future<Purchase> settlePurchasePayment(',
    );
    expect(purchasePath,
        contains('await PaymentVoucherService(sqliteDb).createPayment('));
    expect(purchasePath,
        contains('await _refreshAccountTransactionsFromSqlite();'));
    expect(purchasePath, isNot(contains('_upsertAccountTransactionInternal(')));
  });
}
