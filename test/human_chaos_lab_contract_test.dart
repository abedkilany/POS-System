import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final stressLab = File('lib/features/dev_tools/stress_lab_page.dart');
  final salesPage = File('lib/features/sales/sales_page.dart');
  final purchasesPage = File('lib/features/purchases/purchases_page.dart');
  final cashPage = File('lib/features/cash/cash_page.dart');
  final expensesPage = File('lib/features/expenses/expenses_page.dart');

  test('human chaos lab exposes configurable rookie and chaos modes', () {
    final source = stressLab.readAsStringSync();
    for (final token in const <String>[
      '_HumanChaosMode.standard',
      '_HumanChaosMode.newEmployee',
      '_HumanChaosMode.chaos',
      '_HumanChaosMode.disaster',
      '_HumanChaosMode.marathon',
      'HUMAN_CHAOS_START',
      'HUMAN_CHAOS_DONE',
      'Production Integrity',
      'doubleSubmitSimulation',
      'reloadSimulation',
    ]) {
      expect(source, contains(token), reason: token);
    }
  });

  test('chaos episodes include rookie mistakes plus supervisor recovery', () {
    final source = stressLab.readAsStringSync();
    final start = source.indexOf('Future<String> _runHumanChaosEpisode(');
    final end = source.indexOf('Future<void> _runHumanChaosExtension(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    for (final scenario in const <String>[
      'Stale purchase edit was accepted.',
      'Unused received purchase edit did not repost.',
      'Sale overpayment was accepted.',
      'Cumulative over-return was accepted.',
      'Impossible discount was accepted.',
      'Zero-quantity purchase was accepted.',
      'Consumed purchase batch return was accepted.',
      'wrong customer',
      'wrong supplier',
      'Negative sale quantity was accepted.',
      'Purchase overpayment was accepted.',
      'Zero customer receipt was accepted.',
      'Empty sale document was accepted.',
      'Empty purchase document was accepted.',
      'Received purchase deletion was accepted.',
      'Sale cancellation after partial return was accepted.',
      'Both concurrent Return submits failed.',
    ]) {
      expect(body, contains(scenario), reason: scenario);
    }

    expect(body, contains('store.cancelSale('));
    expect(body, contains('store.returnSale('));
    expect(body, contains('store.returnPurchase('));
    expect(body, contains('store.updatePurchaseDraft('));
    expect(body, contains('store.deleteDraftPurchase('));
    expect(body, contains('_humanChaosReceivedPurchaseItem('));
    expect(source, contains('product.expiryTrackingEnabled'));
    expect(body, contains('purchaseBatchIds.contains(allocation.batchId)'));
  });

  test('each chaos episode is checked for net-neutral recovery and integrity', () {
    final source = stressLab.readAsStringSync();
    final start = source.indexOf('Future<void> _runHumanChaosExtension(');
    final end = source.indexOf('Future<void> _confirmRealUserScenario()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    expect(body, contains('_captureHumanChaosState('));
    expect(body, contains('_assertHumanChaosStateUnchanged('));
    expect(body, contains('_assertHumanChaosIntegrity('));
    expect(body, contains('_reloadHumanChaosState('));
    expect(body, contains('netNeutral=true'));
  });

  test('chaos mutation path does not add direct SQL writes', () {
    final source = stressLab.readAsStringSync();
    final start = source.indexOf('Future<String> _runHumanChaosEpisode(');
    final end = source.indexOf('Future<void> _confirmRealUserScenario()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    for (final forbidden in const <String>[
      '.customStatement(',
      '.into(',
      '.insert(',
      '.update(',
      '.delete(',
      'INSERT INTO',
      'UPDATE ',
      'DELETE FROM',
    ]) {
      expect(body, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('critical sales and purchase UI controls expose stable E2E keys', () {
    final sales = salesPage.readAsStringSync();
    final purchases = purchasesPage.readAsStringSync();

    for (final key in const <String>[
      'SalesContinuePaymentMobile',
      'SalesContinuePaymentDesktop',
      'SalesPaymentDiscountField',
      'SalesPaymentDiscountPercentField',
      'SalesConfirmPaymentButton',
      'SalesReturnConfirmButton',
    ]) {
      expect(sales, contains("ValueKey('$key')"), reason: key);
    }
    for (final key in const <String>[
      'PurchaseBatchSaveButton',
      'PurchaseDeleteDraftConfirmButton',
      'PurchaseReturnReasonField',
      'PurchaseReturnConfirmButton',
    ]) {
      expect(purchases, contains("ValueKey('$key')"), reason: key);
    }

    final cash = cashPage.readAsStringSync();
    for (final key in const <String>[
      'CashReceiptAmountField',
      'CashRefundAmountField',
      'CashRefundConfirmButton',
    ]) {
      expect(cash, contains("ValueKey('$key')"), reason: key);
    }

    final expenses = expensesPage.readAsStringSync();
    for (final key in const <String>[
      'ExpensePostCashButton',
      'ExpensePostCreditButton',
      'ExpenseCancelReasonField',
      'ExpenseCancelConfirmButton',
    ]) {
      expect(expenses, contains("ValueKey('$key')"), reason: key);
    }
  });
}
