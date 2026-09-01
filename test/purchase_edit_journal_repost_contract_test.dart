import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test('received purchase edit is guarded by downstream Unified Batch usage', () {
    final store = readAppStoreImplementationSource();
    final start = store.indexOf('Future<Purchase> updatePurchaseDraft({');
    final end = store.indexOf('Future<void> receivePurchase(', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final editPath = store.substring(start, end);

    expect(editPath, contains('if (current.isDraft)'));
    expect(editPath, contains('else if (current.isReceived)'));
    expect(
      editPath,
      contains('await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, current);'),
    );
    expect(editPath, contains('clearPostedSnapshot: current.isReceived'));
    expect(editPath, contains('_receivedPurchasePaymentStatus('));
    expect(
      editPath,
      contains('PostedDocumentSnapshotService.forPurchase('),
    );
    expect(
      editPath,
      contains('_rebuildProductCostsFromUnifiedBatchesInTransaction('),
    );
    expect(
      editPath,
      contains("referenceId: '\${updated.id}:purchase_edit:v\${updated.version}'"),
    );
    expect(editPath, contains('purchase_edit:v'));
    expect(editPath, contains(r'Purchase edit reverse v${current.version}'));
  });

  test('purchase accounting rejects stale posted snapshots before posting', () {
    final accounting =
        File('lib/core/services/accounting_service.dart').readAsStringSync();
    expect(accounting, contains('_requirePurchasePostedSnapshotMatches('));
    expect(accounting, contains("mismatch('line identity at index \$index')"));
    expect(accounting, contains("mismatch('line values at index \$index')"));
    expect(accounting, contains("mismatch('totals')"));
  });

  test('receivePurchase can suppress normal accounting queue for edit repost',
      () {
    final store = readAppStoreImplementationSource();
    final start = store.indexOf('Future<void> receivePurchase(');
    final end = store.indexOf('Future<void> cancelPurchase(', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final receivePath = store.substring(start, end);

    expect(receivePath, contains('bool postAccounting = true'));
    expect(receivePath, contains('if (postAccounting) {'));
    expect(receivePath, contains('_schedulePurchaseAccounting(received)'));
  });

  test('purchase reversal covers base and all purchase_edit references', () {
    final accounting =
        File('lib/core/services/accounting_service.dart').readAsStringSync();

    expect(
      accounting,
      contains("Variable<String>('\$normalizedPurchaseId:purchase_edit:')"),
    );
    expect(
      accounting,
      contains("AND (reference_id = ? OR instr(reference_id, ?) = 1)"),
    );
    expect(
      accounting,
      contains('reversePurchaseEntriesForPurchase({'),
    );
    expect(
      accounting,
      contains('while (remaining > 0)'),
    );
  });
}
