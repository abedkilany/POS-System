import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  final appStore = readAppStoreImplementationSource();
  final audit = File(
    'lib/core/services/accounting_production_integrity_service.dart',
  ).readAsStringSync();

  String methodBody(String signature, String nextSignature) {
    final start = appStore.indexOf(signature);
    expect(start, isNonNegative, reason: 'Missing $signature');
    final end = appStore.indexOf(nextSignature, start + signature.length);
    expect(end, isNonNegative, reason: 'Missing boundary $nextSignature');
    return appStore.substring(start, end);
  }

  test('expiry adjustment requires accounting journal before commit', () {
    final body = methodBody(
      'Future<void> adjustExpiryBatchStock({',
      'Future<void> reverseExpiryBatchAdjustment(',
    );
    expect(body, contains('Expiry stock loss requires a posted accounting journal.'));
    expect(body, contains('Batch inventory adjustment requires a posted accounting journal.'));
    expect(body, contains("referenceType: 'inventory_waste'"));
    expect(body, contains("referenceType: 'inventory_adjustment'"));
    expect(body, contains('await _requirePostedJournalInTransaction('));
  });

  test('expiry and waste reversal are owned by outer SQLite transaction', () {
    final expiry = methodBody(
      'Future<void> reverseExpiryBatchAdjustment(',
      'Future<void> recordWasteLoss({',
    );
    expect(expiry, contains('withinExistingTransaction: true'));
    expect(expiry, contains('await _requirePostedJournalInTransaction('));
    expect(expiry, contains('await _requireNoActiveJournalInTransaction('));

    final group = methodBody(
      'Future<void> reverseWasteLossGroup(String movementId) async {',
      'Future<void> deleteWasteLoss(String movementId) async {',
    );
    expect(group, contains('withinExistingTransaction: true'));
    expect(group, contains('await _requirePostedJournalInTransaction('));
    expect(group, contains('await _requireNoActiveJournalInTransaction('));

    final single = methodBody(
      'Future<void> deleteWasteLoss(String movementId) async {',
      'void _applyPurchaseStock(Purchase purchase, DateTime now) {',
    );
    expect(single, contains('withinExistingTransaction: true'));
    expect(single, contains('AccountingService.notifyCommittedMutation();'));
  });

  test('waste and inventory count cannot commit material change without journal', () {
    final waste = methodBody(
      'Future<void> recordWasteLoss({',
      'Future<void> reverseWasteLossGroup(String movementId) async {',
    );
    expect(waste, contains('Waste loss requires a posted accounting journal.'));
    expect(waste, contains('await _requirePostedJournalInTransaction('));

    expect(
      appStore,
      contains('Inventory count variance requires a posted accounting journal.'),
    );
    expect(
      appStore,
      contains('Inventory count journal was not persisted; approval was rolled back.'),
    );
  });

  test('production audit is read only and gates critical invariants', () {
    expect(audit, contains('class AccountingProductionIntegrityService'));
    expect(audit, contains('bool get isProductionReady => criticalCount == 0;'));
    expect(audit, contains("code: 'unbalanced_or_empty_journal'"));
    expect(audit, contains("code: 'orphan_journal_line'"));
    expect(audit, contains("code: 'journal_account_missing'"));
    expect(audit, contains("code: 'duplicate_active_posting'"));
    expect(audit, contains("code: 'sale_missing_active_journal'"));
    expect(audit, contains("code: 'returned_sale_missing_return_journal'"));
    expect(audit, contains("code: 'received_purchase_missing_active_journal'"));
    expect(audit, contains("code: 'manufacturing_journal_integrity'"));
    expect(audit, contains("code: 'inventory_count_journal_integrity'"));
    expect(audit, contains("code: 'orphan_stock_reversal'"));
    expect(audit, contains("code: 'unified_batch_quantity_mismatch'"));
    expect(audit, contains("code: 'voucher_allocation_refund_mismatch'"));
    expect(audit, contains("code: 'cash_location_gl_mismatch'"));
    expect(audit, contains("code: '\${partyType}_control_balance_mismatch'"));
    expect(audit, contains("code: 'inventory_gl_valuation_mismatch'"));
    expect(audit, isNot(contains('customInsert(')));
    expect(audit, isNot(contains('customUpdate(')));
    expect(audit, isNot(contains('customStatement(')));
  });

  test('Unified Batch quantity audit is always enabled in Phase 4', () {
    expect(audit, contains('unified_batch_quantity_mismatch'));
    expect(
      audit,
      contains('ABS(COALESCE(w.qty, 0) - COALESCE(b.qty, 0)) > 0.005'),
    );
    expect(audit, contains('post_cutover_unbatched_stock_out'));
  });
}
