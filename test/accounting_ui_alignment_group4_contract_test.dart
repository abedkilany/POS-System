import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  final group1 = File('test/accounting_ui_alignment_group1_contract_test.dart')
      .readAsStringSync();
  final group2 = File('test/accounting_ui_alignment_group2_contract_test.dart')
      .readAsStringSync();
  final group3 = File('test/accounting_ui_alignment_group3_contract_test.dart')
      .readAsStringSync();
  final page = File('lib/features/accounting/accounting_page.dart')
      .readAsStringSync();
  final snapshot =
      File('lib/features/accounting/accounting_snapshot_service.dart')
          .readAsStringSync();
  final reportsPage = File('lib/features/reports/reports_page.dart')
      .readAsStringSync();
  final reportsSnapshot =
      File('lib/features/reports/reports_snapshot_service.dart')
          .readAsStringSync();
  final sqliteStore =
      File('lib/core/storage/sqlite/business_sqlite_store.dart')
          .readAsStringSync();
  final appStore = readAppStoreImplementationSource();
  final accountingMetricsTest =
      File('test/sqlite_accounting_metrics_test.dart').readAsStringSync();
  final integrity = File(
    'lib/core/services/accounting_production_integrity_service.dart',
  ).readAsStringSync();
  final closureTool = File('tool/accounting_closure_audit.py').readAsStringSync();

  test('closure preserves Group 1 cash and account-role contracts', () {
    expect(group1, contains('cash movement UI is sourced from Cash Ledger'));
    expect(group1, contains('accounting summary cash totals are sourced from cash ledger'));
    expect(group1, contains('subledger transaction UI uses debit and credit semantics'));
    expect(group1, contains('financial report UI passes selected period to report services'));
    expect(group1, contains('legacy default account mapping is no longer editable in settings UI'));
  });

  test('closure preserves Group 2 financial-reporting contracts', () {
    expect(group2, contains('general ledger exposes real accounting filters and opening balance'));
    expect(group2, contains('trial balance separates debit and credit balances and checks equality'));
    expect(group2, contains('income statement has account-level financial breakdowns'));
    expect(group2, contains('balance sheet is classified and carries a visible balance status'));
    expect(group2, contains('cash flow report presents period and closing-cash reconciliation'));
  });

  test('closure preserves Group 3 UX and journal drill-down contracts', () {
    expect(group3, contains('accounting navigation separates operations from subledgers'));
    expect(group3, contains('journal entries are first-class UI with filters and drill-down'));
    expect(group3, contains('cash movement has unified direction type and date filters'));
    expect(group3, contains('journal drill-down is reachable from operational accounting views'));
    expect(group3, contains('status badges replace ambiguous journal status presentation'));
  });

  test('accounting dashboard is fully GL and Cash-Ledger aligned', () {
    expect(snapshot, contains('accounting_metrics_summary_v3'));
    expect(snapshot, contains('AccountingService.incomeStatementReport('));
    expect(snapshot, contains('AccountingService.listCashBalancesReport()'));
    expect(page, contains('amount: metrics.cashBalance'));
    expect(page, contains('amount: metrics.bankBalance'));
    expect(page, contains('amount: metrics.monthNetSales'));
    expect(page, contains('amount: metrics.monthGrossProfit'));
    expect(page, contains('amount: metrics.monthExpenses'));
    expect(page, contains('amount: metrics.monthNetProfit'));
  });

  test('general Reports page no longer exposes legacy estimated profit or subledger cash', () {
    final reportsStart = sqliteStore.indexOf(
      'static Future<Map<String, Object?>> buildReportsSummary(',
    );
    final reportsEnd = sqliteStore.indexOf(
      'static Future<Map<String, Object?>> buildAccountingMetrics(',
      reportsStart,
    );
    final reportsSql = sqliteStore.substring(reportsStart, reportsEnd);
    expect(reportsPage, isNot(contains('estimated_profit')));
    expect(reportsPage, isNot(contains('estimatedProfit')));
    expect(reportsSnapshot, isNot(contains('estimatedProfit')));
    expect(reportsSnapshot, contains('CashLedgerService.current().summary('));
    expect(reportsSnapshot, contains('AccountingService.incomeStatementReport('));
    expect(reportsSql, contains('FROM cash_ledger_transactions'));
    expect(reportsSql, contains("INNER JOIN journal_entries je"));
    expect(reportsSql, contains("INNER JOIN accounts a"));
    expect(reportsSql, contains("'netProfit':"));
    expect(reportsSql, isNot(contains("'estimatedProfit':")));
  });

  test('accounting cash management is review-only and leaves daily operations to Cash page', () {
    expect(page, contains('هذه الصفحة للمراجعة والتحليل فقط'));
    expect(page, contains('عمليات فتح وإغلاق الوردية والتحويلات النقدية اليومية تُنفذ من صفحة الصندوق'));
    expect(page, isNot(contains('Future<void> _openDrawerDialog() async')));
    expect(page, isNot(contains('Future<void> _createCashTransferDialog() async')));
    expect(page, isNot(contains('Future<void> _closeDrawerDialog(')));
  });

  test('accounting UI has no corrupted Arabic placeholder strings', () {
    expect(page, isNot(contains('???')));
    expect(page, contains('رقابة النقد والبنوك'));
  });

  test('cash accounting metric fixture follows Cash Ledger authority', () {
    expect(
      accountingMetricsTest,
      contains('INSERT INTO cash_ledger_transactions'),
    );
    expect(accountingMetricsTest, contains("direction: 'in'"));
    expect(accountingMetricsTest, contains("direction: 'out'"));
    expect(
      accountingMetricsTest,
      contains("expect(metrics['todayCashIn'], 80)"),
    );
    expect(
      accountingMetricsTest,
      contains("expect(metrics['todayCashOut'], 90)"),
    );
  });

  test('FIFO sale restoration ignores duplicate FIFO-only history rows', () {
    expect(
      appStore,
      contains('bool _saleBelongsToCurrentFifoPeriod(DateTime saleDate)'),
    );
    expect(appStore, contains('item.method != InventoryCostingMethod.fifo'));
    expect(
      appStore,
      contains('item.costingMethodAtSale == InventoryCostingMethod.fifo'),
    );
    expect(
      appStore,
      contains('_saleBelongsToCurrentFifoPeriod(originalSaleDate)'),
    );
  });

  test('purchase reversal closes persisted layers atomically in SQLite', () {
    expect(
      appStore,
      contains('UPDATE inventory_cost_layers'),
    );
    expect(
      appStore,
      contains('SET quantity_remaining = 0'),
    );
    expect(
      appStore,
      contains('WHERE purchase_id = ?'),
    );
    expect(
      appStore,
      contains('SELECT COALESCE(SUM(quantity_remaining), 0) AS qty'),
    );
    expect(
      appStore,
      contains('cost layers did not close atomically'),
    );
    expect(
      appStore,
      contains('final consumed = activeLayers.any'),
    );
  });

  test('production integrity gate covers accounting closure invariants', () {
    expect(integrity, contains('unbalanced_or_empty_journal'));
    expect(integrity, contains('orphan_journal_line'));
    expect(integrity, contains('journal_account_missing'));
    expect(integrity, contains('cash_voucher_missing_cash_ledger'));
    expect(integrity, contains('voucher_allocation_refund_mismatch'));
    expect(integrity, contains("partyType: 'customer'"));
    expect(integrity, contains("partyType: 'supplier'"));
    expect(integrity, contains("_control_balance_mismatch'"));
    expect(integrity, contains('cash_location_gl_mismatch'));
    expect(integrity, contains('inventory_gl_valuation_mismatch'));
  });

  test('read-only closure utility covers GL cash and subledger reconciliation', () {
    expect(closureTool, contains('mode=ro'));
    expect(closureTool, contains('trial_balance_mismatch'));
    expect(closureTool, contains('cash_location_gl_mismatch'));
    expect(closureTool, contains('party_type="customer"'));
    expect(closureTool, contains('party_type="supplier"'));
    expect(closureTool, contains('_subledger_vs_control'));
    expect(closureTool, contains('cash_ledger_net'));
  });
}
