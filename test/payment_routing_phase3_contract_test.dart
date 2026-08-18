import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phase 3 routes operational cash settlement through voucher methods', () {
    final cashPage = File('lib/features/cash/cash_page.dart').readAsStringSync();
    expect(cashPage, contains('settleSalePayment('));
    expect(cashPage, contains('settlePurchasePayment('));
    expect(cashPage, isNot(contains('widget.store.editSale(')));
    expect(cashPage, isNot(contains('widget.store.editReceivedPurchase(')));
  });

  test('phase 3 separates invoice accounting from voucher payment posting', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    final accounting =
        File('lib/core/services/accounting_service.dart').readAsStringSync();

    expect(appStore, contains('PaymentVoucherService(sqliteDb).createReceipt('));
    expect(appStore, contains('PaymentVoucherService(sqliteDb).createPayment('));
    expect(appStore, contains("idempotencyKey: '\${sale.id}:initial-payment:v1'"));
    expect(appStore,
        contains("idempotencyKey: '\${purchase.id}:initial-payment:v1'"));
    expect(appStore, contains('paymentPostedSeparately: true'));
    expect(accounting, contains('bool paymentPostedSeparately = false'));
  });

  test('phase 3 does not allow lowering allocated payments by invoice edit', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    expect(
      appStore,
      contains('Payments cannot be reduced by editing the invoice. Use payment reversal.'),
    );
    expect(
      appStore,
      contains('Payments cannot be reduced by editing the purchase. Use payment reversal.'),
    );
  });

  test('initial sale payment uses internal settlement without salesEdit permission', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    expect(appStore, contains('Future<Sale> _settleSalePaymentInternal({'));
    expect(appStore, contains('return _settleSalePaymentInternal('));
    expect(appStore, contains('sale = await _settleSalePaymentInternal('));
    expect(appStore, contains('requirePermission(AppPermission.salesEdit);'));
  });

  test('sale and purchase settlement flush account transactions and sync', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
    final matches = RegExp(
      r'await _saveDirty\(accountTransactions: true, sync: true\);',
    ).allMatches(appStore).length;
    expect(matches, greaterThanOrEqualTo(4));
  });

  // Regression guard: invoice correction must not manufacture payment reversals.
  test('invoice edits reverse invoice compatibility only, not voucher payments', () {
    final appStore = File('lib/data/app_store.dart').readAsStringSync();
  
    expect(appStore, contains('void _recordSaleInvoiceCorrectionLedger('));
    expect(appStore, contains('void _recordPurchaseInvoiceCorrectionLedger('));
    expect(
      appStore,
      contains('_recordSaleInvoiceCorrectionLedger(\n      current,\n      now,\n      editVersion: editVersion,'),
    );
    expect(
      appStore,
      contains('_recordPurchaseInvoiceCorrectionLedger(\n      current,\n      now,\n      editVersion: editVersion,'),
    );
    expect(appStore, isNot(contains('_recordSaleCancelLedger(current, now);')));
    expect(
      appStore,
      isNot(contains("_recordPurchaseCancelLedger(current, now, reason: 'Purchase corrected');")),
    );
  
    final saleCorrectionStart = appStore.indexOf('void _recordSaleInvoiceCorrectionLedger(');
    final saleCancelStart = appStore.indexOf('void _recordSaleCancelLedger(', saleCorrectionStart);
    final saleCorrection = appStore.substring(saleCorrectionStart, saleCancelStart);
    expect(saleCorrection, isNot(contains("type: 'paymentReversal'")));
  
    final purchaseCorrectionStart = appStore.indexOf('void _recordPurchaseInvoiceCorrectionLedger(');
    final purchaseCancelStart = appStore.indexOf('void _recordPurchaseCancelLedger(', purchaseCorrectionStart);
    final purchaseCorrection = appStore.substring(purchaseCorrectionStart, purchaseCancelStart);
    expect(purchaseCorrection, isNot(contains("type: 'paymentReversal'")));
  });
}
