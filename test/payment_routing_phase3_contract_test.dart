import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test('phase 3 routes operational cash settlement through voucher methods',
      () {
    final cashPage =
        File('lib/features/cash/cash_page.dart').readAsStringSync();
    expect(cashPage, contains('settleSalePayment('));
    expect(cashPage, contains('settlePurchasePayment('));
    expect(cashPage, isNot(contains('editSale(')));
  });

  test('phase 3 separates invoice accounting from voucher payment posting', () {
    final appStore = readAppStoreImplementationSource();
    final accounting =
        File('lib/core/services/accounting_service.dart').readAsStringSync();

    expect(
        appStore, contains('PaymentVoucherService(sqliteDb).createReceipt('));
    expect(
        appStore, contains('PaymentVoucherService(sqliteDb).createPayment('));
    expect(
        appStore, contains("idempotencyKey: '\${sale.id}:initial-payment:v1'"));
    expect(appStore,
        contains("idempotencyKey: '\${purchase.id}:initial-payment:v1'"));
    expect(appStore, contains('paymentPostedSeparately: true'));
    expect(accounting, contains('bool paymentPostedSeparately = false'));
  });

  test('invoice editing is no longer part of the sale store', () {
    final appStore = readAppStoreImplementationSource();
    expect(appStore, isNot(contains('editSale(')));
    expect(appStore, isNot(contains('sale_edit_correction')));
  });

  test(
      'initial sale payment uses internal settlement without invoice edit permission',
      () {
    final appStore = readAppStoreImplementationSource();
    expect(appStore, contains('Future<Sale> _settleSalePaymentInternal({'));
    expect(appStore, contains('return _settleSalePaymentInternal('));
    expect(appStore, contains('sale = await _settleSalePaymentInternal('));
    expect(appStore,
        contains('requirePermission(AppPermission.customersPaymentManage);'));
  });

  test('sale and purchase settlement flush account transactions and sync', () {
    final appStore = readAppStoreImplementationSource();
    const flush =
        'await _saveDirty(accountTransactions: true, sync: true);';

    final saleSettlement = RegExp(
      r'Future<Sale> _settleSalePaymentInternal\(\{[\s\S]*?Future<Purchase> settlePurchasePayment\(\{',
    ).firstMatch(appStore)?.group(0) ?? '';
    final purchaseSettlement = RegExp(
      r'Future<Purchase> settlePurchasePayment\(\{[\s\S]*?PurchaseItem _copyPurchaseItemWith\(\{',
    ).firstMatch(appStore)?.group(0) ?? '';

    expect(saleSettlement, contains('await refreshAccountTransactionsFromSqlite();'));
    expect(saleSettlement, contains(flush));
    expect(purchaseSettlement, contains('await refreshAccountTransactionsFromSqlite();'));
    expect(purchaseSettlement, contains(flush));
  });
}
