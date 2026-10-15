import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/accounting_page_source.dart';
import 'helpers/accounting_service_source.dart';
import 'helpers/sales_page_source.dart';

import 'helpers/dart_library_source.dart';

void main() {
  test('receipt and payment edits keep append-only allocation history', () {
    final vouchers =
        readDartLibrarySource('lib/core/services/payment_voucher_service.dart');
    final schema = readDartLibrarySource(
        'lib/core/storage/sqlite/ventio_drift_database.dart');
    final appStore =
        readDartLibrarySource('lib/data/app_store_warehouse_cash.dart');

    expect(vouchers, contains('Future<ReceiptVoucher> editReceipt({'));
    expect(vouchers, contains('Future<PaymentVoucher> editPayment({'));
    expect(vouchers, contains(':receipt_edit:v'));
    expect(vouchers, contains(':payment_edit:v'));
    expect(vouchers, contains("status = 'reversed'"));
    expect(vouchers, contains('PostedDocumentEditPipeline<ReceiptVoucher>('));
    expect(vouchers, contains('PostedDocumentEditPipeline<PaymentVoucher>('));
    expect(schema,
        contains('idx_payment_allocations_target_per_voucher_kind_active'));
    expect(schema, contains("status = 'active'"));
    expect(appStore, contains('editReceiptVoucher({'));
    expect(appStore, contains('editPaymentVoucher({'));
  });

  test('posted expense edit is versioned and cancel remains family-aware', () {
    final expenses = readDartLibrarySource(
        'lib/data/app_store_catalog_parties_expenses.dart');
    final accounting = readAccountingServiceSource();
    final reversal =
        File('lib/core/services/cash_reversal_service.dart').readAsStringSync();
    final ui =
        readDartLibrarySource('lib/features/expenses/expenses_page.dart');

    expect(expenses, contains('Future<Expense> editPostedExpense({'));
    expect(expenses, contains('PostedDocumentEditPipeline<Expense>('));
    expect(expenses, contains(':expense_edit:v'));
    expect(accounting, contains(r"'$normalizedReferenceId:expense_edit:'"));
    expect(reversal, contains(':expense_edit:'));
    expect(ui, contains('widget.store.editPostedExpense('));
  });

  test(
      'completed warehouse transfer edit reverses and rebuilds batch movements',
      () {
    final store =
        readDartLibrarySource('lib/data/app_store_warehouse_cash.dart');
    final ui = File('lib/features/inventory/warehouse_transfer_page.dart')
        .readAsStringSync();

    expect(store, contains('editWarehouseTransferOrder({'));
    expect(
        store, contains('PostedDocumentEditPipeline<WarehouseTransferOrder>('));
    expect(store, contains(':transfer_edit:v'));
    expect(store, contains('has a downstream movement'));
    expect(store, contains('reversalOfMovementId: original.id'));
    expect(store, contains('transferUnifiedInTransaction('));
    expect(ui, contains('_beginEditOrder('));
    expect(ui, contains('editWarehouseTransferOrder('));
  });

  test('manual journal edit is restricted to manual entries and versioned', () {
    final accounting = readAccountingServiceSource();
    final ui = readAccountingPageImplementationSource();

    expect(accounting, contains('editManualJournalEntry({'));
    expect(accounting, contains("current.referenceType != 'manual_journal'"));
    expect(accounting, contains("current.source != 'manual'"));
    expect(accounting, contains(':manual_edit:v'));
    expect(accounting,
        contains('PostedDocumentEditPipeline<JournalEntryDetailsReport>('));
    expect(ui, contains('_editManualJournal('));
    expect(ui, contains('AccountingService.editManualJournalEntry('));
  });

  test('manual stock adjustment edit is versioned and batch-safe', () {
    final inventory =
        readDartLibrarySource('lib/data/app_store_inventory.dart');
    final accounting = readAccountingServiceSource();
    final ui =
        readDartLibrarySource('lib/features/inventory/inventory_page.dart');

    expect(inventory, contains('Future<void> editStockAdjustment({'));
    expect(inventory,
        contains('PostedDocumentEditPipeline<List<StockMovement>>('));
    expect(inventory, contains(':inventory_adjustment_edit:v'));
    expect(inventory, contains('downstream consumption'));
    expect(accounting,
        contains(r"'$normalizedReferenceId:inventory_adjustment_edit:'"));
    expect(ui, contains('_editManualAdjustment('));
    expect(ui, contains('widget.store.editStockAdjustment('));
  });

  test(
      'sale return edit rebuilds stock accounting snapshot and version history',
      () {
    final returns =
        readDartLibrarySource('lib/data/app_store_sales_returns.dart');
    final note = File('lib/models/credit_note.dart').readAsStringSync();
    final accounting = readAccountingServiceSource();
    final ui = readSalesPageImplementationSource();

    expect(returns, contains('Future<CreditNote> editSaleReturn({'));
    expect(returns, contains('PostedDocumentEditPipeline<CreditNote>('));
    expect(returns, contains(':sale_return_edit:v'));
    expect(
        returns,
        contains(
            'Only the latest active return for a sale can be edited safely.'));
    expect(returns, contains('PostedDocumentSnapshotService.forSaleReturn('));
    expect(returns, contains('recordSaleReturn('));
    expect(note, contains('final String operationReferenceId;'));
    expect(note, contains('final int version;'));
    expect(accounting, contains(r"'$normalizedReferenceId:sale_return_edit:'"));
    expect(ui, contains('_editLatestSaleReturn('));
    expect(ui, contains('widget.store.editSaleReturn('));
  });

  test('completed manufacturing edit is atomic versioned and batch-traceable',
      () {
    final manufacturing =
        readDartLibrarySource('lib/data/app_store_manufacturing.dart');
    final accounting = readAccountingServiceSource();
    final traceability =
        File('lib/core/services/inventory_traceability_service.dart')
            .readAsStringSync();
    final ui =
        readDartLibrarySource('lib/features/inventory/manufacturing_page.dart');

    expect(
        manufacturing,
        contains(
            'Future<ManufacturingOrder> editCompletedManufacturingOrder({'));
    expect(manufacturing,
        contains('PostedDocumentEditPipeline<ManufacturingOrder>('));
    expect(manufacturing, contains(':manufacturing_edit:v'));
    expect(manufacturing, contains('withinExistingTransactionInternal: true'));
    expect(manufacturing, contains('suppressPostCommitInternal: true'));
    expect(manufacturing, contains('downstream consumption'));
    expect(
        accounting, contains(r"'$normalizedReferenceId:manufacturing_edit:'"));
    expect(traceability, contains('movement_group_id = ?'));
    expect(traceability, contains('operationReferenceId'));
    expect(ui, contains('editCompletedManufacturingOrder('));
    expect(ui, contains('editCompleted: true'));
  });

  test(
      'purchase return edit rebuilds and re-reverses stock accounting atomically',
      () {
    final purchases =
        readDartLibrarySource('lib/data/app_store_purchases.dart');
    final ui =
        readDartLibrarySource('lib/features/purchases/purchases_page.dart');

    expect(purchases, contains('Future<Purchase> editPurchaseReturn({'));
    expect(purchases, contains('PostedDocumentEditPipeline<Purchase>('));
    expect(purchases, contains(':purchase_return_edit:v'));
    expect(purchases, contains('purchase_return_edit_rebuild'));
    expect(purchases, contains('AccountingService.recordPurchase('));
    expect(purchases, contains('reversePurchaseEntriesForPurchase('));
    expect(purchases,
        contains('Edited purchase return left an active stock receipt.'));
    expect(purchases,
        contains('Edited purchase return left an active purchase journal.'));
    expect(ui, contains('widget.store.editPurchaseReturn('));
    expect(ui, contains('editingReturnedPurchase'));
  });
}
