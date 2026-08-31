import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File('lib/features/accounting/accounting_page.dart')
      .readAsStringSync();
  final accountingService =
      File('lib/core/services/accounting_service.dart').readAsStringSync();

  test('accounting navigation separates operations from subledgers', () {
    expect(page, contains('TabController(length: 5'));
    expect(page, contains('class _OperationsAccountingGroup'));
    expect(page, contains('class _AccountsAccountingGroup'));
    expect(page, contains("'العمليات المحاسبية'"));
    expect(page, contains("'الحسابات المساعدة'"));
    expect(page, contains("'التقارير المالية'"));
    expect(page, contains("'الإدارة'"));
    expect(page, contains('if (_tabController.index <= 2)'));
  });

  test('journal entries are first-class UI with filters and drill-down', () {
    expect(page, contains('class _JournalEntriesTab'));
    expect(page, contains('class _JournalEntriesFilterBar'));
    expect(page, contains('_showJournalDrillDown('));
    expect(page, contains('class _JournalDetailsCard'));
    expect(page, contains('class _AccountingStatusBadge'));

    expect(accountingService, contains('listJournalEntrySummaries({'));
    expect(accountingService, contains('journalEntryDetails({'));
    expect(accountingService, contains('class JournalEntrySummaryReport'));
    expect(accountingService, contains('class JournalEntryDetailsReport'));
    expect(accountingService, contains('FROM journal_entries je'));
    expect(accountingService, contains('JOIN journal_lines jl'));
  });

  test('cash movement has unified direction type and date filters', () {
    expect(page, contains('class _CashLedgerFilterBar'));
    expect(page, contains('direction: _direction'));
    expect(page, contains('type: _type'));
    expect(page, contains('from: _from'));
    expect(page, contains('to: _to'));
    expect(page, contains("value: 'in'"));
    expect(page, contains("value: 'out'"));
  });

  test('journal drill-down is reachable from operational accounting views', () {
    expect(page, contains('_showJournalForCashLedgerTransaction('));
    expect(page, contains('_showJournalForAccountTransaction('));
    expect(page, contains('entryNo: line.entryNo'));
    expect(page, contains('entryId: row.journalEntryId'));
    expect(accountingService, contains('ct.journal_entry_id AS reference_id'));
  });

  test('status badges replace ambiguous journal status presentation', () {
    expect(page, contains('class _AccountingStatusBadge'));
    expect(page, contains("'posted' || 'active'"));
    expect(page, contains("'reversed' || 'void'"));
    expect(page, contains("'draft' || 'pending'"));
    expect(page, contains('_AccountingStatusBadge(status: item.status)'));
  });
}
