import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 9 financial atomicity - phase 2 contracts', () {
    test('expense posting commits expense row and compatibility ledger with accounting', () {
      final source = File('lib/core/services/accounting_service.dart').readAsStringSync();
      final start = source.indexOf('static Future<void> recordExpense(Expense expense)');
      final end = source.indexOf('static Future<void> recordExpensesBulk', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('await _db.transaction(() async {'));
      expect(body, contains('await _upsertExpenseRowInExistingTransaction(expense);'));
      expect(body, contains('await _recordExpenseInExistingTransaction(expense, accounts);'));
      expect(body, contains('await _recordExpenseCompatibilityLedgerInExistingTransaction(expense);'));
    });

    test('expense cancellation finalizes status and compatibility reversals inside reversal transaction', () {
      final source = File('lib/core/services/cash_reversal_service.dart').readAsStringSync();
      final txStart = source.indexOf('final result = await _db.transaction(() async {');
      final txEnd = source.indexOf('AccountingService.notifyCommittedMutation();', txStart);
      expect(txStart, greaterThanOrEqualTo(0));
      expect(txEnd, greaterThan(txStart));
      final body = source.substring(txStart, txEnd);
      expect(body, contains("if (cleanType == 'expense')"));
      expect(body, contains('await _finalizeExpenseCancellationInExistingTransaction('));
      expect(source, contains("SET expense_status = 'Cancelled'"));
      expect(source, contains(r"'$expenseId-expense-debit-reversal'"));
      expect(source, contains(r"'$expenseId-expense-credit-reversal'"));
    });

    test('supplier refunds expose a stable refund key and key journal/ledger reference by it', () {
      final service = File('lib/core/services/payment_voucher_service.dart').readAsStringSync();
      final start = service.indexOf('Future<double> refundPurchaseCash({');
      final end = service.indexOf('/// Phase 6:', start);
      expect(start, greaterThanOrEqualTo(0));
      final body = service.substring(start, end > start ? end : service.length);
      expect(body, contains("String refundKey = ''"));
      expect(body, contains(r"final refundReferenceId = '$cleanPurchaseId:$resolvedRefundKey';"));
      expect(body, contains(r"final refundIdempotencyKey = 'purchase_refund:$refundReferenceId';"));
      expect(body, contains('referenceId: refundReferenceId'));
      expect(body, contains('idempotencyKey: refundIdempotencyKey'));

      final store = File('lib/data/app_store.dart').readAsStringSync();
      final storeStart = store.indexOf('Future<double> refundPurchaseCash({');
      final storeEnd = store.indexOf('/// Records a customer receipt', storeStart);
      final storeBody = store.substring(storeStart, storeEnd);
      expect(storeBody, contains("String idempotencyKey = ''"));
      expect(storeBody, contains('refundKey: refundKey'));
    });

    test('customer refund and voucher reversal retain transaction-owned compatibility ledger', () {
      final voucher = File('lib/core/services/payment_voucher_service.dart').readAsStringSync();
      expect(voucher, contains('await _insertCompatibilityRefundMovement('));
      expect(voucher, contains('Future<bool> _reverseVoucher({'));
      expect(voucher, contains('account_transactions'));
      expect(voucher, contains("status == 'reversed' || status == 'void'"));
    });
  });
}
