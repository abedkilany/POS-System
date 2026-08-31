import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File('lib/features/accounting/accounting_page.dart')
      .readAsStringSync();
  final snapshot =
      File('lib/features/accounting/accounting_snapshot_service.dart')
          .readAsStringSync();
  final sqliteStore =
      File('lib/core/storage/sqlite/business_sqlite_store.dart')
          .readAsStringSync();
  final accountingService =
      File('lib/core/services/accounting_service.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  final accountLedgerWidgets =
      File('lib/features/accounts/account_ledger_widgets.dart')
          .readAsStringSync();

  test('cash movement UI is sourced from Cash Ledger', () {
    expect(page, contains('class _CashLedgerTransactionsTab'));
    expect(page, contains('CashLedgerService.current().list('));
    expect(page, contains('transaction.isCashIn'));
    expect(
      page,
      isNot(contains('builder: (_) => _TransactionsTab(\n'
          '                        store: store,\n'
          '                        query: query,\n'
          '                        cashOnly: true')),
    );
  });

  test('accounting summary cash totals are sourced from cash ledger', () {
    final metricsStart = sqliteStore.indexOf(
      'static Future<Map<String, Object?>> buildAccountingMetrics(',
    );
    final metricsEnd = sqliteStore.indexOf(
      'static Future<List<Map<String, Object?>>> queryAccountingAccountRows(',
      metricsStart,
    );
    final metricsSource = sqliteStore.substring(metricsStart, metricsEnd);
    expect(metricsSource, contains('FROM cash_ledger_transactions'));
    expect(metricsSource, contains("direction = 'in'"));
    expect(metricsSource, contains("direction = 'out'"));
    expect(metricsSource, isNot(contains('balances.todayCashIn')));
    expect(metricsSource, isNot(contains('balances.todayCashOut')));
    expect(snapshot, contains('accounting_metrics_summary_v3'));
    expect(snapshot, contains('CashLedgerService.current().summary('));
    expect(snapshot, isNot(contains('bool _isCashIn(')));
    expect(snapshot, isNot(contains('bool _isCashOut(')));
  });

  test('subledger transaction UI uses debit and credit semantics', () {
    expect(page, isNot(contains('_displaySign(')));
    expect(page, contains("Text(tr.text('debit')"));
    expect(page, contains("Text(tr.text('credit')"));
    expect(page, contains('final debitText = transaction.debit > 0'));
    expect(page, contains('final creditText = transaction.credit > 0'));
    expect(accountLedgerWidgets, contains('final isDebit = transaction.debit > 0'));
    expect(
      accountLedgerWidgets,
      contains("text(isDebit ? 'debit' : 'credit')"),
    );
    expect(accountLedgerWidgets, isNot(contains("final sign =")));
    expect(accountLedgerWidgets, isNot(contains("Text('\$sign")));
  });

  test('financial report UI passes selected period to report services', () {
    expect(page, contains('enum _AccountingReportRangeMode'));
    expect(page, contains('class _AccountingReportRangeBar'));
    expect(page, contains('AccountingService.listAccountingPeriods()'));
    expect(
      page,
      contains('AccountingService.trialBalanceReport(from: from, to: to)'),
    );
    expect(
      page,
      contains('AccountingService.incomeStatementReport(from: from, to: to)'),
    );
    expect(
      page,
      contains('AccountingService.cashFlowStatementReport(from: from, to: to)'),
    );
    expect(
      page,
      contains('AccountingService.taxReport(from: from, to: to)'),
    );
    expect(
      page,
      contains('AccountingService.balanceSheetReport(asOf: asOf)'),
    );
    expect(
      accountingService,
      contains('incomeStatementReport({\n    DateTime? from,\n    DateTime? to,'),
    );
    expect(
      accountingService,
      contains('balanceSheetReport({DateTime? asOf})'),
    );
  });

  test('legacy default account mapping is no longer editable in settings UI', () {
    final settingsStart =
        page.indexOf('class _AccountingSettingsTabState');
    final settingsEnd = page.indexOf('class _AccountingSettingsData', settingsStart);
    final settingsSource = page.substring(settingsStart, settingsEnd);
    expect(settingsSource, isNot(contains('readDefaultAccountMap')));
    expect(settingsSource, isNot(contains('updateDefaultAccount')));
    expect(settingsSource, contains('readDefaultVatRatePercent'));
    expect(settingsSource, contains('Account Roles'));
  });
}
