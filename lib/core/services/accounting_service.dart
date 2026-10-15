// ignore_for_file: unused_import
import 'dart:math';
import 'package:drift/drift.dart';
import '../../models/account_transaction.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/expense.dart';
import '../../models/journal_entry.dart';
import '../../models/manufacturing.dart';
import '../../models/purchase.dart';
import '../../models/posted_document_snapshot.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/store_profile.dart';
import '../../models/user_role.dart';
import '../repositories/business_session_context.dart';
import '../accounting/accounting_account_role.dart';
import '../localization/localized_domain_exception.dart';
import '../utils/currency_utils.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import 'cash_balance_policy_service.dart';
import 'cash_ledger_service.dart';
import 'posted_document_edit_framework.dart';
import 'unified_batch_phase4_closure_service.dart';
import 'accounting_service_impl.dart' as impl;
import 'accounting_service_models.dart';
export 'accounting_service_models.dart';

class AccountingService {
  AccountingService._();
  static const String deferredBomInventoryReconciliationKey =
      'inventory_bom_account_reconciliation_pending_v1';
  static const Set<String> supportedAccountTypes = <String>{
    'asset',
    'liability',
    'equity',
    'revenue',
    'cost_of_sales',
    'expense'
  };
  static const Set<String> supportedNormalBalances = <String>{
    'debit',
    'credit'
  };
  static bool get isAvailable => impl.isAvailable;
  static void setMutationListener(void Function()? listener) =>
      impl.setMutationListener(listener);
  static void notifyCommittedMutation() => impl.notifyCommittedMutation();
  static void configureMoneyPolicy(StoreProfile profile) =>
      impl.configureMoneyPolicy(profile);
  static bool get allowNegativeCashBalance => impl.allowNegativeCashBalance;
  static Future<void> ensureCashOutflowAllowed(
          {required String cashLocationId,
          required double amount,
          VentioDriftDatabase? database}) =>
      impl.ensureCashOutflowAllowed(
          cashLocationId: cashLocationId, amount: amount, database: database);
  static Future<void> applyCashLocationDelta(
          {required String cashLocationId,
          required double delta,
          required String updatedAt,
          VentioDriftDatabase? database}) =>
      impl.applyCashLocationDelta(
          cashLocationId: cashLocationId,
          delta: delta,
          updatedAt: updatedAt,
          database: database);
  static Future<String> resolveInventoryRoleKeyForProduct(String productId) =>
      impl.resolveInventoryRoleKeyForProduct(productId);
  static Future<String> resolveInventoryAccountForProductForDatabase(
          VentioDriftDatabase database, String productId) =>
      impl.resolveInventoryAccountForProductForDatabase(database, productId);
  static Future<bool> ensureInventoryAccountClassificationMigration() =>
      impl.ensureInventoryAccountClassificationMigration();
  static Future<bool> reconcileInventoryAccountClassification(
          {String referenceContext = 'runtime',
          VentioDriftDatabase? database,
          bool withinExistingTransaction = false}) =>
      impl.reconcileInventoryAccountClassification(
          referenceContext: referenceContext,
          database: database,
          withinExistingTransaction: withinExistingTransaction);
  static Future<void> deferBomInventoryAccountReconciliation(
          {required String referenceContext, VentioDriftDatabase? database}) =>
      impl.deferBomInventoryAccountReconciliation(
          referenceContext: referenceContext, database: database);
  static Future<List<AccountingAccount>> listAccounts(
          {bool activeOnly = true}) =>
      impl.listAccounts(activeOnly: activeOnly);
  static Future<AccountingAccount> createAccount(
          {required String code,
          required String name,
          required String type,
          required String normalBalance,
          String subtype = '',
          String parentId = '',
          String currency = 'USD',
          String description = '',
          bool isPostable = true,
          String storeId = '',
          String branchId = ''}) =>
      impl.createAccount(
          code: code,
          name: name,
          type: type,
          normalBalance: normalBalance,
          subtype: subtype,
          parentId: parentId,
          currency: currency,
          description: description,
          isPostable: isPostable,
          storeId: storeId,
          branchId: branchId);
  static Future<void> updateAccount(
          {required String accountId,
          required String code,
          required String name,
          required String type,
          required String normalBalance,
          String subtype = '',
          String parentId = '',
          String currency = 'USD',
          String description = '',
          bool isPostable = true}) =>
      impl.updateAccount(
          accountId: accountId,
          code: code,
          name: name,
          type: type,
          normalBalance: normalBalance,
          subtype: subtype,
          parentId: parentId,
          currency: currency,
          description: description,
          isPostable: isPostable);
  static Future<void> setAccountActive(
          {required String accountId, required bool active}) =>
      impl.setAccountActive(accountId: accountId, active: active);
  static Future<void> deleteAccount(String accountId) =>
      impl.deleteAccount(accountId);
  static Future<double> readDefaultVatRatePercent() =>
      impl.readDefaultVatRatePercent();
  static Future<void> updateDefaultVatRatePercent(double ratePercent,
          {required BusinessSessionContext authorization}) =>
      impl.updateDefaultVatRatePercent(ratePercent,
          authorization: authorization);
  static Future<Map<String, String>> readDefaultAccountMap() =>
      impl.readDefaultAccountMap();
  static Future<Map<String, String>> readAccountRoleMap() =>
      impl.readAccountRoleMap();
  static Future<String> resolveAccountRole(String roleKey) =>
      impl.resolveAccountRole(roleKey);
  static Future<String> resolveAccountRoleForDatabase(
          VentioDriftDatabase database, String roleKey) =>
      impl.resolveAccountRoleForDatabase(database, roleKey);
  static Future<Map<String, String>> readResolvedAccountRoleMap() =>
      impl.readResolvedAccountRoleMap();
  static Future<List<String>> validateAccountRoleConfiguration() =>
      impl.validateAccountRoleConfiguration();
  static Future<void> updateAccountRole(
          {required String roleKey, required String accountId}) =>
      impl.updateAccountRole(roleKey: roleKey, accountId: accountId);
  static Future<void> updateDefaultAccount(
          {required String key, required String accountId}) =>
      impl.updateDefaultAccount(key: key, accountId: accountId);
  static Future<void> recordSale(Sale sale,
          {String? accountingReferenceId,
          bool paymentPostedSeparately = false,
          bool withinExistingTransaction = false}) =>
      impl.recordSale(sale,
          accountingReferenceId: accountingReferenceId,
          paymentPostedSeparately: paymentPostedSeparately,
          withinExistingTransaction: withinExistingTransaction);
  static Future<String> recordSaleReturn(
          {required Sale sale,
          required String returnReferenceId,
          required DateTime date,
          required double returnAmount,
          required double returnCogs,
          List<SaleItem> returnedItems = const <SaleItem>[],
          PostedDocumentSnapshot? returnSnapshot,
          String createdBy = '',
          bool withinExistingTransaction = false}) =>
      impl.recordSaleReturn(
          sale: sale,
          returnReferenceId: returnReferenceId,
          date: date,
          returnAmount: returnAmount,
          returnCogs: returnCogs,
          returnedItems: returnedItems,
          returnSnapshot: returnSnapshot,
          createdBy: createdBy,
          withinExistingTransaction: withinExistingTransaction);
  static Future<bool> recordPurchase(Purchase purchase,
          {String accountingReferenceId = '',
          bool paymentPostedSeparately = false,
          bool withinExistingTransaction = false}) =>
      impl.recordPurchase(purchase,
          accountingReferenceId: accountingReferenceId,
          paymentPostedSeparately: paymentPostedSeparately,
          withinExistingTransaction: withinExistingTransaction);
  static Future<void> validatePurchasePayment(
          {required String paymentMethod,
          required double paidAmount,
          required String deviceId,
          required String branchId}) =>
      impl.validatePurchasePayment(
          paymentMethod: paymentMethod,
          paidAmount: paidAmount,
          deviceId: deviceId,
          branchId: branchId);
  static String expenseAccountRoleKeyForReport(Expense expense) =>
      impl.expenseAccountRoleKeyForReport(expense);
  static Future<void> recordExpense(Expense expense,
          {double? cashPaidAmount}) =>
      impl.recordExpense(expense, cashPaidAmount: cashPaidAmount);
  static Future<void> recordExpenseOnCredit(Expense expense) =>
      impl.recordExpenseOnCredit(expense);
  static Future<void> repostEditedExpenseInExistingTransaction(Expense expense,
          {required bool paidInCash,
          double? cashPaidAmount,
          required String technicalReferenceId}) =>
      impl.repostEditedExpenseInExistingTransaction(expense,
          paidInCash: paidInCash,
          cashPaidAmount: cashPaidAmount,
          technicalReferenceId: technicalReferenceId);
  static Future<Set<String>> readOutstandingCreditExpenseIds() =>
      impl.readOutstandingCreditExpenseIds();
  static Future<Map<String, double>> readOutstandingCreditExpenseBalances() =>
      impl.readOutstandingCreditExpenseBalances();
  static Future<String> resolveCreditExpensePayableAccount(String expenseId) =>
      impl.resolveCreditExpensePayableAccount(expenseId);
  static Future<void> recordExpensesBulk(List<Expense> expenses) =>
      impl.recordExpensesBulk(expenses);
  static Future<String> postVoucherPayment(
          {required VentioDriftDatabase database,
          required String voucherType,
          required String voucherId,
          required String voucherNo,
          required DateTime date,
          required double amount,
          double discount = 0,
          required String paymentMethod,
          required String partyId,
          required String partyName,
          String cashLocationId = '',
          String createdBy = '',
          String storeId = '',
          String branchId = '',
          String accountingReferenceId = '',
          bool withinExistingTransaction = false}) =>
      impl.postVoucherPayment(
          database: database,
          voucherType: voucherType,
          voucherId: voucherId,
          voucherNo: voucherNo,
          date: date,
          amount: amount,
          discount: discount,
          paymentMethod: paymentMethod,
          partyId: partyId,
          partyName: partyName,
          cashLocationId: cashLocationId,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          accountingReferenceId: accountingReferenceId,
          withinExistingTransaction: withinExistingTransaction);
  static Future<void> recordAccountPayment(AccountTransaction transaction,
          {VentioDriftDatabase? database,
          bool withinExistingTransaction = false,
          bool notifyChange = true}) =>
      impl.recordAccountPayment(transaction,
          database: database,
          withinExistingTransaction: withinExistingTransaction,
          notifyChange: notifyChange);
  static Future<String> createPostedEntry(JournalEntryDraft draft,
          {VentioDriftDatabase? database,
          bool withinExistingTransaction = false}) =>
      impl.createPostedEntry(draft,
          database: database,
          withinExistingTransaction: withinExistingTransaction);
  static Future<int> countPostedJournalEntriesForReferences(
          {required String referenceType,
          required Iterable<String> referenceIds}) =>
      impl.countPostedJournalEntriesForReferences(
          referenceType: referenceType, referenceIds: referenceIds);
  static Future<int> countPostedSaleEntriesForSale(String saleId) =>
      impl.countPostedSaleEntriesForSale(saleId);
  static Future<void> reverseSaleEntriesForSale(
          {required String saleId,
          String reason = '',
          String createdBy = '',
          bool adjustCashLocationBalance = true,
          bool notifyChange = true,
          bool withinExistingTransaction = false}) =>
      impl.reverseSaleEntriesForSale(
          saleId: saleId,
          reason: reason,
          createdBy: createdBy,
          adjustCashLocationBalance: adjustCashLocationBalance,
          notifyChange: notifyChange,
          withinExistingTransaction: withinExistingTransaction);
  static Future<int> countPostedPurchaseEntriesForPurchase(String purchaseId) =>
      impl.countPostedPurchaseEntriesForPurchase(purchaseId);
  static Future<void> reversePurchaseEntriesForPurchase(
          {required String purchaseId,
          String reason = '',
          String createdBy = '',
          bool adjustCashLocationBalance = true,
          bool notifyChange = true,
          bool withinExistingTransaction = false}) =>
      impl.reversePurchaseEntriesForPurchase(
          purchaseId: purchaseId,
          reason: reason,
          createdBy: createdBy,
          adjustCashLocationBalance: adjustCashLocationBalance,
          notifyChange: notifyChange,
          withinExistingTransaction: withinExistingTransaction);
  static Future<void> reverseEntryForReference(
          {required String referenceType,
          required String referenceId,
          String reason = '',
          String createdBy = '',
          bool adjustCashLocationBalance = true,
          bool notifyChange = true,
          bool withinExistingTransaction = false}) =>
      impl.reverseEntryForReference(
          referenceType: referenceType,
          referenceId: referenceId,
          reason: reason,
          createdBy: createdBy,
          adjustCashLocationBalance: adjustCashLocationBalance,
          notifyChange: notifyChange,
          withinExistingTransaction: withinExistingTransaction);
  static Future<List<JournalEntrySummaryReport>> listJournalEntrySummaries(
          {DateTime? from,
          DateTime? to,
          String status = '',
          String source = '',
          String search = '',
          int limit = 500}) =>
      impl.listJournalEntrySummaries(
          from: from,
          to: to,
          status: status,
          source: source,
          search: search,
          limit: limit);
  static Future<List<JournalEntryDetailsReport>> journalEntryDetails(
          {String entryId = '',
          String entryNo = '',
          String referenceType = '',
          String referenceId = '',
          String referenceNo = ''}) =>
      impl.journalEntryDetails(
          entryId: entryId,
          entryNo: entryNo,
          referenceType: referenceType,
          referenceId: referenceId,
          referenceNo: referenceNo);
  static Future<List<GeneralLedgerAccountReport>> generalLedgerReport(
          {String accountId = '',
          DateTime? from,
          DateTime? to,
          String branchId = '',
          String costCenterId = ''}) =>
      impl.generalLedgerReport(
          accountId: accountId,
          from: from,
          to: to,
          branchId: branchId,
          costCenterId: costCenterId);
  static Future<List<TrialBalanceRowReport>> trialBalanceReport(
          {DateTime? from, DateTime? to}) =>
      impl.trialBalanceReport(from: from, to: to);
  static Future<IncomeStatementReport> incomeStatementReport(
          {DateTime? from, DateTime? to}) =>
      impl.incomeStatementReport(from: from, to: to);
  static Future<BalanceSheetReport> balanceSheetReport({DateTime? asOf}) =>
      impl.balanceSheetReport(asOf: asOf);
  static Future<List<InventoryValuationRowReport>> inventoryValuationReport(
          {VentioDriftDatabase? database}) =>
      impl.inventoryValuationReport(database: database);
  static Future<List<ManufacturingOrderCostReport>>
      manufacturingOrderCostReport() => impl.manufacturingOrderCostReport();
  static Future<List<ManufacturingWasteReportRow>> manufacturingWasteReport() =>
      impl.manufacturingWasteReport();
  static Future<List<InventoryCountVarianceReportRow>>
      inventoryCountVarianceReport() => impl.inventoryCountVarianceReport();
  static Future<List<CashBankMovementReport>> cashBankMovementReport() =>
      impl.cashBankMovementReport();
  static Future<CashFlowStatementReport> cashFlowStatementReport(
          {DateTime? from, DateTime? to}) =>
      impl.cashFlowStatementReport(from: from, to: to);
  static Future<TaxReport> taxReport({DateTime? from, DateTime? to}) =>
      impl.taxReport(from: from, to: to);
  static Future<List<AdvancedAccountingItem>> listPaymentAccounts() =>
      impl.listPaymentAccounts();
  static Future<List<AdvancedAccountingItem>> listActiveCashLocations(
          {bool includeBank = true}) =>
      impl.listActiveCashLocations(includeBank: includeBank);
  static Future<bool> hasOpenCashDrawerForDevice(
          {required String deviceId, String branchId = ''}) =>
      impl.hasOpenCashDrawerForDevice(deviceId: deviceId, branchId: branchId);
  static Future<AdvancedAccountingItem?> currentCashDrawerForDevice(
          {required String deviceId, String branchId = ''}) =>
      impl.currentCashDrawerForDevice(deviceId: deviceId, branchId: branchId);
  static Future<bool> hasOpenCashDrawer(
          {String branchId = '', String cashLocationId = ''}) =>
      impl.hasOpenCashDrawer(
          branchId: branchId, cashLocationId: cashLocationId);
  static Future<String> currentOpenCashDrawerSessionId(
          {String branchId = '', String cashLocationId = ''}) =>
      impl.currentOpenCashDrawerSessionId(
          branchId: branchId, cashLocationId: cashLocationId);
  static Future<List<AdvancedAccountingItem>> listCashLocations() =>
      impl.listCashLocations();
  static Future<List<AdvancedAccountingItem>> listCashTransfers() =>
      impl.listCashTransfers();
  static Future<List<CashShiftReportSession>> listClosedCashDrawerSessions(
          {int limit = 200}) =>
      impl.listClosedCashDrawerSessions(limit: limit);
  static Future<List<AdvancedAccountingItem>> listCashDrawers() =>
      impl.listCashDrawers();
  static Future<List<AdvancedAccountingItem>> listCashBalancesReport() =>
      impl.listCashBalancesReport();
  static Future<List<AdvancedAccountingItem>> listOpenCashDrawersReport() =>
      impl.listOpenCashDrawersReport();
  static Future<List<AdvancedAccountingItem>> listCashDrawerVarianceReport(
          {int limit = 100}) =>
      impl.listCashDrawerVarianceReport(limit: limit);
  static Future<List<AdvancedAccountingItem>> listCashTransferAuditReport(
          {int limit = 100}) =>
      impl.listCashTransferAuditReport(limit: limit);
  static Future<double> calculateCashDrawerExpectedCash(String sessionId) =>
      impl.calculateCashDrawerExpectedCash(sessionId);
  static Future<List<AdvancedAccountingItem>> listCheques() =>
      impl.listCheques();
  static Future<List<AdvancedAccountingItem>> listAccountingPeriods() =>
      impl.listAccountingPeriods();
  static Future<List<AdvancedAccountingItem>> listCostCenters() =>
      impl.listCostCenters();
  static Future<List<AdvancedAccountingItem>> listAccountingBranches() =>
      impl.listAccountingBranches();
  static Future<List<AdvancedAccountingItem>> listGeneralLedgerBranches() =>
      impl.listGeneralLedgerBranches();
  static Future<List<AdvancedAccountingItem>> listFixedAssets() =>
      impl.listFixedAssets();
  static Future<void> createFixedAsset(
          {required String code,
          required String name,
          required String category,
          required DateTime acquisitionDate,
          required double purchaseValue,
          int usefulLifeMonths = 0,
          String assetAccountId = '',
          String paymentAccountId = '',
          bool paidFromCashDrawer = false,
          String currency = 'USD',
          String notes = '',
          String createdBy = '',
          String createdByUserId = '',
          String deviceId = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.createFixedAsset(
          code: code,
          name: name,
          category: category,
          acquisitionDate: acquisitionDate,
          purchaseValue: purchaseValue,
          usefulLifeMonths: usefulLifeMonths,
          assetAccountId: assetAccountId,
          paymentAccountId: paymentAccountId,
          paidFromCashDrawer: paidFromCashDrawer,
          currency: currency,
          notes: notes,
          createdBy: createdBy,
          createdByUserId: createdByUserId,
          deviceId: deviceId,
          storeId: storeId,
          branchId: branchId);
  static Future<int> runDepreciationForAsset(
          {required String assetId,
          DateTime? throughDate,
          String createdBy = ''}) =>
      impl.runDepreciationForAsset(
          assetId: assetId, throughDate: throughDate, createdBy: createdBy);
  static Future<int> runDepreciationForAllAssets(
          {DateTime? throughDate, String createdBy = ''}) =>
      impl.runDepreciationForAllAssets(
          throughDate: throughDate, createdBy: createdBy);
  static Future<void> createManualJournalEntry(
          {required DateTime entryDate,
          required String description,
          required List<JournalLineDraft> lines,
          String createdBy = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.createManualJournalEntry(
          entryDate: entryDate,
          description: description,
          lines: lines,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId);
  static Future<String> editManualJournalEntry(
          {required String activeEntryId,
          required DateTime entryDate,
          required String description,
          required List<JournalLineDraft> lines,
          String createdBy = '',
          String branchId = ''}) =>
      impl.editManualJournalEntry(
          activeEntryId: activeEntryId,
          entryDate: entryDate,
          description: description,
          lines: lines,
          createdBy: createdBy,
          branchId: branchId);
  static Future<String> recordInventoryDeficitCostReconciliationInTransaction(
          {required VentioDriftDatabase database,
          required String settlementId,
          required String productId,
          required String productName,
          required double quantity,
          required double provisionalUnitCost,
          required double actualUnitCost,
          required DateTime entryDate,
          String sourceReferenceId = '',
          String sourceReferenceNo = '',
          String createdBy = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.recordInventoryDeficitCostReconciliationInTransaction(
          database: database,
          settlementId: settlementId,
          productId: productId,
          productName: productName,
          quantity: quantity,
          provisionalUnitCost: provisionalUnitCost,
          actualUnitCost: actualUnitCost,
          entryDate: entryDate,
          sourceReferenceId: sourceReferenceId,
          sourceReferenceNo: sourceReferenceNo,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId);
  static Future<String> recordInventoryDeficitCostVarianceInTransaction(
          {required VentioDriftDatabase database,
          required String settlementId,
          required String productId,
          required String productName,
          required double quantity,
          required double provisionalUnitCost,
          required double actualUnitCost,
          required DateTime entryDate,
          String sourceReferenceId = '',
          String sourceReferenceNo = '',
          String sourceMovementType = '',
          String createdBy = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.recordInventoryDeficitCostVarianceInTransaction(
          database: database,
          settlementId: settlementId,
          productId: productId,
          productName: productName,
          quantity: quantity,
          provisionalUnitCost: provisionalUnitCost,
          actualUnitCost: actualUnitCost,
          entryDate: entryDate,
          sourceReferenceId: sourceReferenceId,
          sourceReferenceNo: sourceReferenceNo,
          sourceMovementType: sourceMovementType,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId);
  static Future<String> recordInventoryBatchRevaluationInTransaction(
          {required VentioDriftDatabase database,
          required DateTime entryDate,
          required String referenceId,
          required String referenceNo,
          required String productId,
          required String productName,
          required String batchId,
          required double valueDelta,
          String createdBy = '',
          String storeId = '',
          String branchId = '',
          String reason = ''}) =>
      impl.recordInventoryBatchRevaluationInTransaction(
          database: database,
          entryDate: entryDate,
          referenceId: referenceId,
          referenceNo: referenceNo,
          productId: productId,
          productName: productName,
          batchId: batchId,
          valueDelta: valueDelta,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          reason: reason);
  static Future<String> recordManualInventoryAdjustmentInTransaction(
          {required VentioDriftDatabase database,
          required DateTime entryDate,
          required String referenceId,
          required String referenceNo,
          required String productId,
          required String productName,
          required double quantityDelta,
          required double value,
          String adjustmentCategory = 'other',
          String reason = '',
          String createdBy = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.recordManualInventoryAdjustmentInTransaction(
          database: database,
          entryDate: entryDate,
          referenceId: referenceId,
          referenceNo: referenceNo,
          productId: productId,
          productName: productName,
          quantityDelta: quantityDelta,
          value: value,
          adjustmentCategory: adjustmentCategory,
          reason: reason,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId);
  static Future<String> recordInventoryWaste(
          {required DateTime entryDate,
          required String referenceId,
          required String referenceNo,
          required double amount,
          required String productName,
          String productId = '',
          String createdBy = '',
          String storeId = '',
          String branchId = '',
          String notes = '',
          String expenseRoleKey = 'inventory_damage',
          VentioDriftDatabase? database,
          bool withinExistingTransaction = false}) =>
      impl.recordInventoryWaste(
          entryDate: entryDate,
          referenceId: referenceId,
          referenceNo: referenceNo,
          amount: amount,
          productName: productName,
          productId: productId,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          notes: notes,
          expenseRoleKey: expenseRoleKey,
          database: database,
          withinExistingTransaction: withinExistingTransaction);
  static Future<String> recordManufacturingCompletionInTransaction(
          {required VentioDriftDatabase database,
          required ManufacturingOrder order,
          String technicalReferenceId = ''}) =>
      impl.recordManufacturingCompletionInTransaction(
          database: database,
          order: order,
          technicalReferenceId: technicalReferenceId);
  static Future<String> recordInventoryCountAdjustment(
          {required DateTime entryDate,
          required String referenceId,
          required String referenceNo,
          required List<InventoryCountVariance> variances,
          String createdBy = '',
          String storeId = '',
          String branchId = '',
          String notes = '',
          VentioDriftDatabase? database,
          bool withinExistingTransaction = false}) =>
      impl.recordInventoryCountAdjustment(
          entryDate: entryDate,
          referenceId: referenceId,
          referenceNo: referenceNo,
          variances: variances,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          notes: notes,
          database: database,
          withinExistingTransaction: withinExistingTransaction);
  static Future<String> reverseInventoryCountAdjustmentInTransaction(
          {required VentioDriftDatabase database,
          required String referenceId,
          String reason = '',
          String createdBy = ''}) =>
      impl.reverseInventoryCountAdjustmentInTransaction(
          database: database,
          referenceId: referenceId,
          reason: reason,
          createdBy: createdBy);
  static Future<void> recordOpeningCashLocationBalance(
          {required String cashLocationId,
          required double amount,
          String storeId = '',
          String branchId = '',
          String createdBy = '',
          String notes = ''}) =>
      impl.recordOpeningCashLocationBalance(
          cashLocationId: cashLocationId,
          amount: amount,
          storeId: storeId,
          branchId: branchId,
          createdBy: createdBy,
          notes: notes);
  static Future<void> openCashDrawer(
          {required BusinessSessionContext authorization,
          required String drawerNo,
          required double openingBalance,
          String cashLocationId = '',
          String fundingLocationId = '',
          String openedBy = '',
          String openedByUserId = '',
          String storeId = '',
          String branchId = '',
          String deviceId = ''}) =>
      impl.openCashDrawer(
          authorization: authorization,
          drawerNo: drawerNo,
          openingBalance: openingBalance,
          cashLocationId: cashLocationId,
          fundingLocationId: fundingLocationId,
          openedBy: openedBy,
          openedByUserId: openedByUserId,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId);
  static Future<void> closeCashDrawer(
          {required BusinessSessionContext authorization,
          required String sessionId,
          required double countedCash,
          String closedBy = '',
          String closedByUserId = '',
          String notes = '',
          String depositToLocationId = ''}) =>
      impl.closeCashDrawer(
          authorization: authorization,
          sessionId: sessionId,
          countedCash: countedCash,
          closedBy: closedBy,
          closedByUserId: closedByUserId,
          notes: notes,
          depositToLocationId: depositToLocationId);
  static Future<void> createAccountingPeriod(
          {required String name,
          required DateTime startDate,
          required DateTime endDate,
          String createdBy = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.createAccountingPeriod(
          name: name,
          startDate: startDate,
          endDate: endDate,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId);
  static Future<void> closeAccountingPeriod(
          {required String periodId, String closedBy = ''}) =>
      impl.closeAccountingPeriod(periodId: periodId, closedBy: closedBy);
  static Future<void> createCashLocation(
          {required String name,
          required String type,
          String code = '',
          String accountId = '',
          String paymentAccountId = '',
          bool isDefault = false,
          String notes = '',
          String storeId = '',
          String branchId = '',
          String deviceId = '',
          String createdBy = ''}) =>
      impl.createCashLocation(
          name: name,
          type: type,
          code: code,
          accountId: accountId,
          paymentAccountId: paymentAccountId,
          isDefault: isDefault,
          notes: notes,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          createdBy: createdBy);
  static Future<void> linkCashDrawerToDevice(
          {required String cashLocationId,
          required String deviceId,
          String branchId = ''}) =>
      impl.linkCashDrawerToDevice(
          cashLocationId: cashLocationId,
          deviceId: deviceId,
          branchId: branchId);
  static Future<void> unlinkCashDrawerFromDevice({required String deviceId}) =>
      impl.unlinkCashDrawerFromDevice(deviceId: deviceId);
  static Future<String> createCashTransfer(
          {required BusinessSessionContext authorization,
          required String fromLocationId,
          required String toLocationId,
          required double amount,
          DateTime? transferDate,
          String notes = '',
          String createdBy = '',
          String createdByUserId = '',
          String storeId = '',
          String branchId = '',
          String deviceId = '',
          String fromSessionId = '',
          String toSessionId = '',
          String transferKind = 'vault_transfer',
          String idempotencyKey = '',
          bool notifyChange = true,
          bool withinExistingTransaction = false}) =>
      impl.createCashTransfer(
          authorization: authorization,
          fromLocationId: fromLocationId,
          toLocationId: toLocationId,
          amount: amount,
          transferDate: transferDate,
          notes: notes,
          createdBy: createdBy,
          createdByUserId: createdByUserId,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          fromSessionId: fromSessionId,
          toSessionId: toSessionId,
          transferKind: transferKind,
          idempotencyKey: idempotencyKey,
          notifyChange: notifyChange,
          withinExistingTransaction: withinExistingTransaction);
  static Future<void> createPaymentAccount(
          {required String name,
          required String type,
          required String accountId,
          bool isDefault = false,
          String notes = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.createPaymentAccount(
          name: name,
          type: type,
          accountId: accountId,
          isDefault: isDefault,
          notes: notes,
          storeId: storeId,
          branchId: branchId);
  static Future<void> createCheque(
          {required String chequeNo,
          required String direction,
          required String partyType,
          required String partyId,
          required String partyName,
          required String bankName,
          required DateTime dueDate,
          required double amount,
          String notes = '',
          String storeId = '',
          String branchId = ''}) =>
      impl.createCheque(
          chequeNo: chequeNo,
          direction: direction,
          partyType: partyType,
          partyId: partyId,
          partyName: partyName,
          bankName: bankName,
          dueDate: dueDate,
          amount: amount,
          notes: notes,
          storeId: storeId,
          branchId: branchId);
  static Future<void> settleCheque(
          {required String chequeId, String settledBy = ''}) =>
      impl.settleCheque(chequeId: chequeId, settledBy: settledBy);
  static Future<void> bounceCheque(
          {required String chequeId, String reason = '', String actor = ''}) =>
      impl.bounceCheque(chequeId: chequeId, reason: reason, actor: actor);
  static Future<void> createSimpleMasterData(
          {required String table,
          required String code,
          required String name}) =>
      impl.createSimpleMasterData(table: table, code: code, name: name);
  static Future<void> recordInventoryCountAuditInTransaction(
          {required VentioDriftDatabase database,
          required String action,
          required String inventoryCountId,
          required String details,
          String createdBy = '',
          String storeId = '',
          String branchId = '',
          DateTime? createdAt}) =>
      impl.recordInventoryCountAuditInTransaction(
          database: database,
          action: action,
          inventoryCountId: inventoryCountId,
          details: details,
          createdBy: createdBy,
          storeId: storeId,
          branchId: branchId,
          createdAt: createdAt);
}
