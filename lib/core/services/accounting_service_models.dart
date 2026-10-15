import '../../models/manufacturing.dart';

class InventoryCountVariance {
  const InventoryCountVariance(
      {this.productId = '',
      required this.productName,
      required this.delta,
      required this.amount});
  final String productId;
  final String productName;
  final double delta;
  final double amount;
}

class JournalEntrySummaryReport {
  const JournalEntrySummaryReport(
      {required this.id,
      required this.entryNo,
      required this.entryDate,
      required this.referenceType,
      required this.referenceId,
      required this.referenceNo,
      required this.description,
      required this.status,
      required this.source,
      required this.createdBy,
      required this.branchId,
      required this.reversedEntryId,
      required this.reversedByEntryId,
      required this.reversalReason,
      required this.totalDebit,
      required this.totalCredit,
      required this.lineCount});
  final String id;
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String description;
  final String status;
  final String source;
  final String createdBy;
  final String branchId;
  final String reversedEntryId;
  final String reversedByEntryId;
  final String reversalReason;
  final double totalDebit;
  final double totalCredit;
  final int lineCount;
  factory JournalEntrySummaryReport.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    int integer(String key) =>
        (row[key] as num?)?.toInt() ??
        int.tryParse(row[key]?.toString() ?? '') ??
        0;
    return JournalEntrySummaryReport(
        id: row['id']?.toString() ?? '',
        entryNo: row['entry_no']?.toString() ?? '',
        entryDate: DateTime.tryParse(row['entry_date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        referenceType: row['reference_type']?.toString() ?? '',
        referenceId: row['reference_id']?.toString() ?? '',
        referenceNo: row['reference_no']?.toString() ?? '',
        description: row['description']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        source: row['source']?.toString() ?? '',
        createdBy: row['created_by']?.toString() ?? '',
        branchId: row['branch_id']?.toString() ?? '',
        reversedEntryId: row['reversed_entry_id']?.toString() ?? '',
        reversedByEntryId: row['reversed_by_entry_id']?.toString() ?? '',
        reversalReason: row['reversal_reason']?.toString() ?? '',
        totalDebit: number('total_debit'),
        totalCredit: number('total_credit'),
        lineCount: integer('line_count'));
  }
}

class JournalEntryDetailsReport {
  const JournalEntryDetailsReport(
      {required this.id,
      required this.entryNo,
      required this.entryDate,
      required this.referenceType,
      required this.referenceId,
      required this.referenceNo,
      required this.description,
      required this.status,
      required this.source,
      required this.createdBy,
      required this.branchId,
      required this.reversedEntryId,
      required this.reversedByEntryId,
      required this.reversalReason,
      required this.postedAt,
      required this.reversedAt,
      required this.reversedBy,
      required this.lines});
  final String id;
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String description;
  final String status;
  final String source;
  final String createdBy;
  final String branchId;
  final String reversedEntryId;
  final String reversedByEntryId;
  final String reversalReason;
  final DateTime? postedAt;
  final DateTime? reversedAt;
  final String reversedBy;
  final List<JournalEntryDetailLineReport> lines;
  double get totalDebit =>
      lines.fold<double>(0, (sum, line) => sum + line.debit);
  double get totalCredit =>
      lines.fold<double>(0, (sum, line) => sum + line.credit);
}

class JournalEntryDetailLineReport {
  const JournalEntryDetailLineReport(
      {required this.lineNo,
      required this.accountId,
      required this.accountCode,
      required this.accountName,
      required this.debit,
      required this.credit,
      required this.memo,
      required this.partyType,
      required this.partyId,
      required this.partyName,
      required this.costCenterId});
  final int lineNo;
  final String accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String memo;
  final String partyType;
  final String partyId;
  final String partyName;
  final String costCenterId;
  factory JournalEntryDetailLineReport.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    return JournalEntryDetailLineReport(
        lineNo: (row['line_no'] as num?)?.toInt() ??
            int.tryParse(row['line_no']?.toString() ?? '') ??
            0,
        accountId: row['account_id']?.toString() ?? '',
        accountCode: row['account_code']?.toString() ?? '',
        accountName: row['account_name']?.toString() ?? '',
        debit: number('debit'),
        credit: number('credit'),
        memo: row['memo']?.toString() ?? '',
        partyType: row['party_type']?.toString() ?? '',
        partyId: row['party_id']?.toString() ?? '',
        partyName: row['party_name']?.toString() ?? '',
        costCenterId: row['cost_center_id']?.toString() ?? '');
  }
}

class AdvancedAccountingItem {
  const AdvancedAccountingItem(
      {required this.id,
      required this.name,
      this.type = '',
      this.accountCode = '',
      this.accountName = '',
      this.status = '',
      this.referenceId = '',
      this.notes = '',
      this.debit = 0,
      this.credit = 0,
      this.balance = 0,
      this.isActive = true,
      this.isDefault = false});
  final String id;
  final String name;
  final String type;
  final String accountCode;
  final String accountName;
  final String status;
  final String referenceId;
  final String notes;
  final double debit;
  final double credit;
  final double balance;
  final bool isActive;
  final bool isDefault;
  factory AdvancedAccountingItem.fromRow(Map<String, Object?> row) {
    double toDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool toBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value?.toString() == '1' ||
          value?.toString().toLowerCase() == 'true';
    }

    return AdvancedAccountingItem(
        id: row['id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        type: row['type']?.toString() ?? '',
        accountCode: row['account_code']?.toString() ?? '',
        accountName: row['account_name']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        referenceId: row['reference_id']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
        debit: toDouble(row['debit']),
        credit: toDouble(row['credit']),
        balance: toDouble(row['balance']),
        isActive: !row.containsKey('is_active') || toBool(row['is_active']),
        isDefault: toBool(row['is_default']));
  }
}

class TrialBalanceRowReport {
  const TrialBalanceRowReport(
      {required this.accountId,
      required this.accountCode,
      required this.accountName,
      required this.accountType,
      required this.debit,
      required this.credit,
      required this.balance,
      this.accountSubtype = '',
      this.normalBalance = 'debit',
      this.opening = 0,
      this.closing = 0});
  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final String normalBalance;
  final double debit;
  final double credit;
  final double balance;
  final double opening;
  final double closing;
  double get debitBalance {
    if (normalBalance == 'credit') {
      return closing < 0 ? -closing : 0;
    }
    return closing > 0 ? closing : 0;
  }

  double get creditBalance {
    if (normalBalance == 'credit') {
      return closing > 0 ? closing : 0;
    }
    return closing < 0 ? -closing : 0;
  }
}

class GeneralLedgerAccountReport {
  const GeneralLedgerAccountReport(
      {required this.accountId,
      required this.accountCode,
      required this.accountName,
      required this.accountType,
      required this.normalBalance,
      required this.totalDebit,
      required this.totalCredit,
      required this.closingBalance,
      required this.lines,
      this.accountSubtype = '',
      this.openingBalance = 0});
  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final String normalBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
  final double openingBalance;
  final List<GeneralLedgerLineReport> lines;
}

class GeneralLedgerLineReport {
  const GeneralLedgerLineReport(
      {required this.entryNo,
      required this.entryDate,
      required this.referenceType,
      required this.referenceNo,
      required this.description,
      required this.memo,
      required this.debit,
      required this.credit,
      required this.runningBalance,
      this.referenceId = '',
      this.source = ''});
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String source;
  final String description;
  final String memo;
  final double debit;
  final double credit;
  final double runningBalance;
}

class FinancialStatementAccountLine {
  const FinancialStatementAccountLine(
      {required this.accountId,
      required this.accountCode,
      required this.accountName,
      required this.accountType,
      required this.amount,
      this.accountSubtype = ''});
  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubtype;
  final double amount;
}

class IncomeStatementReport {
  const IncomeStatementReport(
      {required this.revenue,
      required this.costOfGoodsSold,
      required this.grossProfit,
      required this.expenses,
      required this.netProfit,
      this.grossSales = 0,
      this.salesReturns = 0,
      this.salesDiscounts = 0,
      this.netSales = 0,
      this.otherRevenue = 0,
      this.inventoryGain = 0,
      this.cashOver = 0,
      this.inventoryLoss = 0,
      this.manufacturingWaste = 0,
      this.manufacturingVariance = 0,
      this.cashShort = 0,
      this.otherRevenueLines = const <FinancialStatementAccountLine>[],
      this.costOfSalesLines = const <FinancialStatementAccountLine>[],
      this.expenseLines = const <FinancialStatementAccountLine>[]});
  final double revenue;
  final double costOfGoodsSold;
  final double grossProfit;
  final double expenses;
  final double netProfit;
  final double grossSales,
      salesReturns,
      salesDiscounts,
      netSales,
      otherRevenue,
      inventoryGain,
      cashOver,
      inventoryLoss,
      manufacturingWaste,
      manufacturingVariance,
      cashShort;
  final List<FinancialStatementAccountLine> otherRevenueLines;
  final List<FinancialStatementAccountLine> costOfSalesLines;
  final List<FinancialStatementAccountLine> expenseLines;
}

class BalanceSheetReport {
  const BalanceSheetReport(
      {required this.assets,
      required this.liabilities,
      required this.equity,
      required this.retainedEarnings,
      required this.liabilitiesAndEquity,
      required this.difference,
      this.currentAssets = 0,
      this.nonCurrentAssets = 0,
      this.currentLiabilities = 0,
      this.nonCurrentLiabilities = 0,
      this.currentAssetLines = const <FinancialStatementAccountLine>[],
      this.nonCurrentAssetLines = const <FinancialStatementAccountLine>[],
      this.currentLiabilityLines = const <FinancialStatementAccountLine>[],
      this.nonCurrentLiabilityLines = const <FinancialStatementAccountLine>[],
      this.equityLines = const <FinancialStatementAccountLine>[]});
  final double assets;
  final double liabilities;
  final double equity;
  final double retainedEarnings;
  final double liabilitiesAndEquity;
  final double difference;
  final double currentAssets;
  final double nonCurrentAssets;
  final double currentLiabilities;
  final double nonCurrentLiabilities;
  final List<FinancialStatementAccountLine> currentAssetLines;
  final List<FinancialStatementAccountLine> nonCurrentAssetLines;
  final List<FinancialStatementAccountLine> currentLiabilityLines;
  final List<FinancialStatementAccountLine> nonCurrentLiabilityLines;
  final List<FinancialStatementAccountLine> equityLines;
}

enum CashFlowCategory { operating, investing, financing }

class CashFlowStatementReport {
  const CashFlowStatementReport(
      {required this.operatingInflows,
      required this.operatingOutflows,
      required this.investingInflows,
      required this.investingOutflows,
      required this.financingInflows,
      required this.financingOutflows,
      required this.openingCash,
      required this.closingCash,
      this.from,
      this.to,
      this.lines = const <CashFlowStatementLineReport>[]});
  final double operatingInflows;
  final double operatingOutflows;
  final double investingInflows;
  final double investingOutflows;
  final double financingInflows;
  final double financingOutflows;
  final double openingCash;
  final double closingCash;
  final DateTime? from;
  final DateTime? to;
  final List<CashFlowStatementLineReport> lines;
  double get operatingNet => operatingInflows - operatingOutflows;
  double get investingNet => investingInflows - investingOutflows;
  double get financingNet => financingInflows - financingOutflows;
  double get netChangeInCash => operatingNet + investingNet + financingNet;
}

class CashFlowStatementLineReport {
  const CashFlowStatementLineReport(
      {required this.entryNo,
      required this.entryDate,
      required this.referenceType,
      required this.referenceNo,
      required this.description,
      required this.category,
      required this.inflow,
      required this.outflow,
      required this.netCashFlow});
  final String entryNo;
  final DateTime entryDate;
  final String referenceType;
  final String referenceNo;
  final String description;
  final CashFlowCategory category;
  final double inflow;
  final double outflow;
  final double netCashFlow;
}

class TaxReport {
  const TaxReport(
      {required this.outputTax,
      required this.inputTax,
      required this.netTaxPayable,
      required this.payableAccountMovement,
      this.from,
      this.to});
  final double outputTax;
  final double inputTax;
  final double netTaxPayable;
  final double payableAccountMovement;
  final DateTime? from;
  final DateTime? to;
}

class CashBankMovementReport {
  const CashBankMovementReport(
      {required this.accountId,
      required this.accountCode,
      required this.accountName,
      required this.moneyIn,
      required this.moneyOut,
      required this.closingBalance});
  final String accountId;
  final String accountCode;
  final String accountName;
  final double moneyIn;
  final double moneyOut;
  final double closingBalance;
}

class InventoryValuationRowReport {
  const InventoryValuationRowReport(
      {required this.productId,
      required this.productName,
      required this.warehouseId,
      required this.warehouseName,
      required this.quantity,
      required this.unitCost,
      required this.totalValue,
      required this.inventoryAccountId,
      required this.inventoryCategory,
      this.fallbackInventoryAccountId = ''});
  final String productId,
      productName,
      warehouseId,
      warehouseName,
      inventoryAccountId,
      inventoryCategory,
      fallbackInventoryAccountId;
  final double quantity, unitCost, totalValue;
}

class ManufacturingOrderCostReport {
  const ManufacturingOrderCostReport(
      {required this.orderId,
      required this.orderNo,
      required this.outputProductId,
      required this.outputProductName,
      required this.outputQuantity,
      required this.totalMaterialCost,
      required this.wasteValue,
      required this.eligibleCost,
      required this.actualUnitCost,
      required this.status,
      required this.journalEntryId,
      required this.materialCosts});
  final String orderId,
      orderNo,
      outputProductId,
      outputProductName,
      status,
      journalEntryId;
  final double outputQuantity,
      totalMaterialCost,
      wasteValue,
      eligibleCost,
      actualUnitCost;
  final List<ManufacturingMaterialCost> materialCosts;
}

class ManufacturingWasteReportRow {
  const ManufacturingWasteReportRow(
      {required this.orderId,
      required this.orderNo,
      required this.productId,
      required this.productName,
      required this.quantity,
      required this.unitCost,
      required this.value,
      required this.reason,
      required this.status});
  final String orderId, orderNo, productId, productName, reason, status;
  final double quantity, unitCost, value;
}

class InventoryCountVarianceReportRow {
  const InventoryCountVarianceReportRow(
      {required this.sessionId,
      required this.countNo,
      required this.status,
      required this.journalEntryId,
      required this.reversalJournalEntryId,
      required this.productId,
      required this.productName,
      required this.systemQuantity,
      required this.countedQuantity,
      required this.differenceQuantity,
      required this.unitCost,
      required this.differenceValue,
      required this.stockMovementId});
  final String sessionId,
      countNo,
      status,
      journalEntryId,
      reversalJournalEntryId,
      productId,
      productName,
      stockMovementId;
  final double systemQuantity,
      countedQuantity,
      differenceQuantity,
      unitCost,
      differenceValue;
  factory InventoryCountVarianceReportRow.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0;
    return InventoryCountVarianceReportRow(
        sessionId: row['session_id']?.toString() ?? '',
        countNo: row['count_no']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        journalEntryId: row['journal_entry_id']?.toString() ?? '',
        reversalJournalEntryId:
            row['reversal_journal_entry_id']?.toString() ?? '',
        productId: row['product_id']?.toString() ?? '',
        productName: row['product_name']?.toString() ?? '',
        systemQuantity: number('system_qty_at_approval'),
        countedQuantity: number('counted_qty'),
        differenceQuantity: number('difference_qty'),
        unitCost: number('unit_cost'),
        differenceValue: number('difference_value'),
        stockMovementId: row['stock_movement_id']?.toString() ?? '');
  }
}

class CashShiftReportSession {
  const CashShiftReportSession(
      {required this.id,
      required this.drawerNo,
      required this.cashLocationId,
      required this.cashLocationName,
      required this.openedAt,
      required this.closedAt,
      required this.openingBalance,
      required this.expectedCash,
      required this.countedCash,
      required this.difference,
      required this.notes,
      required this.openedBy,
      required this.closedBy,
      required this.branchId});
  final String id;
  final String drawerNo;
  final String cashLocationId;
  final String cashLocationName;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double expectedCash;
  final double countedCash;
  final double difference;
  final String notes;
  final String openedBy;
  final String closedBy;
  final String branchId;
  factory CashShiftReportSession.fromRow(Map<String, Object?> row) {
    double number(String key) =>
        (row[key] as num?)?.toDouble() ??
        double.tryParse(row[key]?.toString() ?? '') ??
        0.0;
    return CashShiftReportSession(
        id: row['id']?.toString() ?? '',
        drawerNo: row['drawer_no']?.toString() ?? '',
        cashLocationId: row['cash_location_id']?.toString() ?? '',
        cashLocationName: row['cash_location_name']?.toString() ?? '',
        openedAt: DateTime.tryParse(row['opened_at']?.toString() ?? ''),
        closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
        openingBalance: number('opening_balance'),
        expectedCash: number('expected_cash'),
        countedCash: number('counted_cash'),
        difference: number('difference'),
        notes: row['notes']?.toString() ?? '',
        openedBy: row['opened_by']?.toString() ?? '',
        closedBy: row['closed_by']?.toString() ?? '',
        branchId: row['branch_id']?.toString() ?? '');
  }
}
