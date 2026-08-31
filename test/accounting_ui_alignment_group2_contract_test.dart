import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File('lib/features/accounting/accounting_page.dart')
      .readAsStringSync();
  final accountingService =
      File('lib/core/services/accounting_service.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

  test('general ledger exposes real accounting filters and opening balance', () {
    expect(page, contains('class _GeneralLedgerFilterBar'));
    expect(page, contains("'general_ledger_report_v2'"));
    expect(page, contains('branchId: _branchId'));
    expect(page, contains('costCenterId: _costCenterId'));
    expect(page, contains("'الرصيد الافتتاحي للفترة'"));
    expect(page, contains("'إجمالي الفترة / الرصيد الختامي'"));

    expect(
      accountingService,
      contains("String branchId = '',\n    String costCenterId = '',"),
    );
    expect(accountingService, contains('listGeneralLedgerBranches()'));
    expect(accountingService, contains("je.branch_id = ?"));
    expect(accountingService, contains("jl.cost_center_id = ?"));
    expect(accountingService, contains('openingBalance: _roundMoney(openingBalance)'));
  });

  test('trial balance separates debit and credit balances and checks equality', () {
    expect(accountingService, contains('double get debitBalance'));
    expect(accountingService, contains('double get creditBalance'));
    expect(page, contains("'رصيد مدين'"));
    expect(page, contains("'رصيد دائن'"));
    expect(page, contains('final movementDifference = totalDebit - totalCredit'));
    expect(
      page,
      contains('final balanceDifference = totalDebitBalance - totalCreditBalance'),
    );
    expect(page, contains("'ميزان المراجعة متوازن'"));
  });

  test('income statement has account-level financial breakdowns', () {
    expect(accountingService, contains('class FinancialStatementAccountLine'));
    expect(accountingService, contains('otherRevenueLines: otherRevenueLines'));
    expect(accountingService, contains('costOfSalesLines: costOfSalesLines'));
    expect(accountingService, contains('expenseLines: expenseLines'));
    expect(page, contains('accountLines: report.costOfSalesLines'));
    expect(page, contains('accountLines: report.otherRevenueLines'));
    expect(page, contains('accountLines: report.expenseLines'));
    expect(page, contains("'تفاصيل الحسابات'"));
  });

  test('balance sheet is classified and carries a visible balance status', () {
    expect(accountingService, contains("subtype == 'fixed_assets'"));
    expect(accountingService, contains("subtype == 'long_term_loans'"));
    expect(accountingService, contains('currentAssetLines: currentAssetLines'));
    expect(accountingService, contains('nonCurrentAssetLines: nonCurrentAssetLines'));
    expect(accountingService, contains('currentLiabilityLines: currentLiabilityLines'));
    expect(accountingService, contains('nonCurrentLiabilityLines: nonCurrentLiabilityLines'));
    expect(page, contains("'الأصول المتداولة'"));
    expect(page, contains("'الأصول غير المتداولة'"));
    expect(page, contains("'الالتزامات المتداولة'"));
    expect(page, contains("'الالتزامات غير المتداولة'"));
    expect(page, contains("'المركز المالي متوازن'"));
  });

  test('cash flow report presents period and closing-cash reconciliation', () {
    expect(page, contains("'cash_flow_report_v2|"));
    expect(
      page,
      contains('report.openingCash + report.netChangeInCash - report.closingCash'),
    );
    expect(page, contains("'التدفقات النقدية متصالحة مع الرصيد'"));
    expect(page, contains('class _FinancialSummaryChip'));
  });
}
