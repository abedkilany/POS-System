import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test('posted sale edit follows the shared safe edit pipeline', () {
    final store = readAppStoreImplementationSource();
    final start = store.indexOf('Future<Sale> editPostedSale({');
    final end = store.indexOf('String _saleStockMovementId({', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final editPath = store.substring(start, end);

    expect(editPath, contains('PostedDocumentEditPipeline<Sale>('));
    expect(editPath, contains('validatePermission:'));
    expect(editPath, contains('validateVersion:'));
    expect(editPath, contains('validateDependencies:'));
    expect(editPath, contains('reverseOperationalEffects:'));
    expect(editPath, contains('reverseAccountingEffects:'));
    expect(editPath, contains('applyChanges:'));
    expect(editPath, contains('rebuildOperationalEffects:'));
    expect(editPath, contains('buildPostedSnapshot:'));
    expect(editPath, contains('repostAccounting:'));
    expect(editPath, contains('rebuildDerivedState:'));
    expect(editPath, contains('verifyIntegrity:'));
    expect(editPath, contains("operationType: 'sale_edit_reverse'"));
    expect(editPath, contains("operationType: 'sale_edit_repost'"));
    expect(editPath, contains('sale_edit:v'));
    expect(editPath, contains('clearPostedSnapshot: true'));
    expect(
      editPath,
      contains('PostedDocumentSnapshotService.forSale('),
    );
    expect(
      editPath,
      contains('AccountingService.reverseSaleEntriesForSale('),
    );
    expect(
      editPath,
      contains('accountingReferenceId: referenceId'),
    );
  });

  test('sale edit protects returns, delivery notes, payments and version races', () {
    final store = readAppStoreImplementationSource();
    final start = store.indexOf('Future<Sale> editPostedSale({');
    final end = store.indexOf('String _saleStockMovementId({', start);
    final editPath = store.substring(start, end);

    expect(editPath, contains('current.version != expectedVersion'));
    expect(editPath, contains('after a sale return was posted'));
    expect(editPath, contains('while a delivery note is linked'));
    expect(editPath, contains('sale with allocated payments'));
    expect(editPath, contains('below its already allocated payment'));
    expect(editPath, contains('_remainingReversibleStockQuantityInTransaction('));
  });

  test('sale edit stock movement identity remains valid across edit and cancel', () {
    final store = readAppStoreImplementationSource();
    expect(store, contains("postedSnapshot?.extra['postedEditVersion']"));
    expect(store, contains('int? operationalVersion'));
    expect(store, contains("'sale-edit-v\$effectiveVersion'"));
    expect(store, contains("'\${sale.id}:sale_edit:v\$effectiveVersion'"));
    expect(store, contains("'postedEditVersion': candidate.version"));

    final cancelStart = store.indexOf('Future<void> cancelSale(');
    final cancelEnd = store.indexOf('Future<void> deleteSale(', cancelStart);
    expect(cancelStart, isNonNegative);
    expect(cancelEnd, greaterThan(cancelStart));
    final cancelPath = store.substring(cancelStart, cancelEnd);
    expect(cancelPath, contains('_saleStockMovementId('));
    expect(cancelPath, contains('includeSaleEditFamily: true'));
    expect(cancelPath, contains('AccountingService.reverseSaleEntriesForSale('));
  });

  test('sale accounting supports versioned edit references and snapshot guards', () {
    final accounting =
        File('lib/core/services/accounting_service.dart').readAsStringSync();

    expect(accounting, contains('String? accountingReferenceId'));
    expect(accounting, contains('_requireSalePostedSnapshotMatches('));
    expect(accounting, contains('countPostedSaleEntriesForSale('));
    expect(accounting, contains('reverseSaleEntriesForSale({'));
    expect(
      accounting,
      contains("Variable<String>('\$normalizedSaleId:sale_edit:')"),
    );
    expect(
      accounting,
      contains("? '\$normalizedReferenceId:sale_edit:'"),
    );
  });

  test('sales edit permission and UI action are exposed', () {
    final permissions = File('lib/models/user_role.dart').readAsStringSync();
    final page = File('lib/features/sales/sales_page.dart').readAsStringSync();

    expect(permissions, contains("static const String salesEdit = 'sales.edit';"));
    expect(permissions, contains("salesEdit: 'Edit posted sales'"));
    expect(page, contains('AppPermission.salesEdit'));
    expect(page, contains("tr.text('edit_sale')"));
    expect(page, contains("ValueKey('SalesEditSaveButton')"));
    expect(page, contains('widget.store.editPostedSale('));
  });
}
