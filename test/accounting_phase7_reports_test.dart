import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/models/journal_entry.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('final reports use posted journal lines and expose contra revenue',
      () async {
    await support.readyPhase5SqliteStore();
    final cash = await AccountingService.resolveAccountRole('cash');
    final sales = await AccountingService.resolveAccountRole('sales_revenue');
    final returns = await AccountingService.resolveAccountRole('sales_returns');
    final discounts =
        await AccountingService.resolveAccountRole('sales_discounts');
    final otherRevenue =
        await AccountingService.resolveAccountRole('other_revenue');
    // Use a dedicated reporting period so this contract is deterministic even
    // when the Flutter test process reuses the same SQLite fixture file.
    final date = DateTime.utc(2036, 2, 17, 12);
    await AccountingService.createPostedEntry(JournalEntryDraft(
      entryDate: date,
      referenceType: 'report_test',
      referenceId: 'report-sale',
      referenceNo: 'R-1',
      description: 'Gross sale with return and discount',
      lines: <JournalLineDraft>[
        JournalLineDraft(accountId: cash, debit: 80, credit: 0),
        JournalLineDraft(accountId: returns, debit: 10, credit: 0),
        JournalLineDraft(accountId: discounts, debit: 10, credit: 0),
        JournalLineDraft(accountId: sales, debit: 0, credit: 100),
      ],
    ));
    await AccountingService.createPostedEntry(JournalEntryDraft(
      entryDate: date,
      referenceType: 'report_test',
      referenceId: 'report-other-income',
      referenceNo: 'R-2',
      description: 'Other income must not inflate gross profit',
      lines: <JournalLineDraft>[
        JournalLineDraft(accountId: cash, debit: 20, credit: 0),
        JournalLineDraft(accountId: otherRevenue, debit: 0, credit: 20),
      ],
    ));

    final periodFrom = DateTime.utc(2036, 2, 17);
    final periodTo = DateTime.utc(2036, 2, 18);
    final income = await AccountingService.incomeStatementReport(
      from: periodFrom,
      to: periodTo,
    );
    expect(income.grossSales, closeTo(100, 0.0001));
    expect(income.salesReturns, closeTo(10, 0.0001));
    expect(income.salesDiscounts, closeTo(10, 0.0001));
    expect(income.netSales, closeTo(80, 0.0001));
    expect(income.otherRevenue, closeTo(20, 0.0001));
    expect(income.grossProfit, closeTo(80, 0.0001));

    final ledger = await AccountingService.generalLedgerReport(
      accountId: cash,
      from: periodFrom,
      to: periodTo,
    );
    expect(ledger, hasLength(1));
    final saleLine = ledger.single.lines
        .firstWhere((line) => line.referenceId == 'report-sale');
    expect(saleLine.source, 'system');
    // The cash ledger includes both the report sale (80) and the separate
    // other-income receipt (20), while the sale line assertion above keeps
    // the source attribution precise.
    expect(ledger.single.closingBalance, closeTo(100, 0.0001));

    final trial = await AccountingService.trialBalanceReport(
      from: periodFrom,
      to: periodTo,
    );
    expect(
      trial.fold<double>(0, (sum, row) => sum + row.debit),
      closeTo(trial.fold<double>(0, (sum, row) => sum + row.credit), 0.0001),
    );
    final balance = await AccountingService.balanceSheetReport();
    expect(balance.difference, closeTo(0, 0.0001));
  });
}
