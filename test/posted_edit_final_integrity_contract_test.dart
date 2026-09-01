import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production integrity recognizes versioned posted-edit families', () {
    final integrity = File(
      'lib/core/services/accounting_production_integrity_service.dart',
    ).readAsStringSync();

    expect(integrity, contains('_checkPostedEditFamilyUniqueness(issues)'));
    expect(integrity, contains('duplicate_active_posted_edit_family'));
    for (final marker in <String>[
      ':sale_edit:',
      ':sale_return_edit:',
      ':purchase_edit:',
      ':receipt_edit:',
      ':payment_edit:',
      ':expense_edit:',
      ':manual_edit:',
      ':inventory_adjustment_edit:',
      ':manufacturing_edit:',
    ]) {
      expect(integrity, contains(marker), reason: 'missing family $marker');
    }

    expect(
      integrity,
      contains("instr(je.reference_id, s.id || ':sale_edit:') = 1"),
    );
    expect(
      integrity,
      contains("instr(je.reference_id, mo.id || ':manufacturing_edit:') = 1"),
    );
    expect(integrity, contains('_checkExpensePosting(issues)'));
    expect(integrity, contains('posted_expense_missing_active_journal'));
    expect(integrity, contains('cancelled_expense_has_active_journal'));
  });

  test('phase7 cash integrity accepts edited vouchers and sales', () {
    final phase7 = File(
      'lib/core/services/cash_phase7_migration_service.dart',
    ).readAsStringSync();

    expect(phase7, contains("s.id || ':sale_edit:'"));
    expect(phase7, contains("v.id || ':receipt_edit:'"));
    expect(phase7, contains("v.id || ':payment_edit:'"));
    expect(phase7, contains('reversed_entry_id = je.id'));
    expect(phase7, contains('reversal_of_id = clt.id'));
  });

  test('manufacturing traceability ignores reversed historical edit movements',
      () {
    final traceability = File(
      'lib/core/services/inventory_traceability_service.dart',
    ).readAsStringSync();

    expect(
      traceability,
      contains('rev.reversal_of_movement_id = sm.id'),
    );
    expect(
      traceability,
      contains('rev.reversal_of_movement_id = scoped.id'),
    );
    expect(traceability, contains('COUNT(DISTINCT b.id)'));
    expect(traceability, contains("sm.movement_type = 'manufacturing_produce'"));
  });

  test('all posted edit APIs remain wired to shared pipeline or safe family', () {
    final files = <String, String>{
      'sales': 'lib/data/app_store_sales_returns.dart',
      'purchases': 'lib/data/app_store_purchases.dart',
      'expenses': 'lib/data/app_store_catalog_parties_expenses.dart',
      'warehouse': 'lib/data/app_store_warehouse_cash.dart',
      'inventory': 'lib/data/app_store_inventory.dart',
      'manufacturing': 'lib/data/app_store_manufacturing.dart',
      'vouchers': 'lib/core/services/payment_voucher_service.dart',
      'accounting': 'lib/core/services/accounting_service.dart',
    };
    final sources = <String, String>{
      for (final entry in files.entries)
        entry.key: File(entry.value).readAsStringSync(),
    };

    expect(sources['sales'], contains('PostedDocumentEditPipeline<Sale>('));
    expect(sources['sales'], contains('PostedDocumentEditPipeline<CreditNote>('));
    expect(sources['purchases'], contains('PostedDocumentEditPipeline<Purchase>('));
    expect(sources['expenses'], contains('PostedDocumentEditPipeline<Expense>('));
    expect(
      sources['warehouse'],
      contains('PostedDocumentEditPipeline<WarehouseTransferOrder>('),
    );
    expect(
      sources['inventory'],
      contains('PostedDocumentEditPipeline<List<StockMovement>>('),
    );
    expect(
      sources['manufacturing'],
      contains('PostedDocumentEditPipeline<ManufacturingOrder>('),
    );
    expect(
      sources['vouchers'],
      contains('PostedDocumentEditPipeline<ReceiptVoucher>('),
    );
    expect(
      sources['vouchers'],
      contains('PostedDocumentEditPipeline<PaymentVoucher>('),
    );
    expect(
      sources['accounting'],
      contains('PostedDocumentEditPipeline<JournalEntryDetailsReport>('),
    );
  });
}
