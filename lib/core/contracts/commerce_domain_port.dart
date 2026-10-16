import '../../models/commerce_overview.dart';
import '../../models/credit_note.dart';
import '../../models/customer.dart';
import '../../models/delivery_note.dart';
import '../../models/expense.dart';
import '../../models/inventory_batch.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/sale_quotation.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/supplier_purchase_price.dart';

abstract class CommerceDomainPort {
  List<Customer> get customers;
  List<Customer> get allCustomersForDiagnostics;
  List<Supplier> get suppliers;
  List<Sale> get sales;
  List<Purchase> get purchases;
  List<Expense> get expenses;
  int get customersRevision;
  int get suppliersRevision;
  int get salesRevision;
  int get salesPageRevision;
  double get totalSalesAmount;
  int get pendingPurchaseCount;
  int get purchasesRevision;
  int get expensesRevision;
  PurchasesOverview get purchasesOverview;
  ExpensesOverview get expensesOverview;
  double get totalPurchasesAmount;
  double get totalExpensesAmount;
  Customer get walkInCustomer;
  List<SaleQuotation> get saleQuotations;
  List<DeliveryNote> get deliveryNotes;
  List<CreditNote> get creditNotes;
  Future<void> ensureCustomersLoaded();
  Future<void> ensureSuppliersLoaded();
  Future<void> ensureSalesLoaded();
  Future<void> ensurePurchasesLoaded();
  Future<void> ensureQuotationsLoaded();
  Future<void> ensureDeliveryNotesLoaded();
  Future<void> ensureCreditNotesLoaded();
  String resolveCustomerName(String? customerId);
  String sanitizeSelectedCustomerId(String? customerId);
  Future<void> addOrUpdateCustomer(Customer customer);
  Future<void> deleteCustomer(String id);
  Future<void> addOrUpdateSupplier(Supplier supplier);
  Future<void> deleteSupplier(String id);
  List<SupplierProductPrice> supplierProductPricesForProduct(
    String productId,
  );
  Future<void> addOrUpdateSupplierProductPrice(SupplierProductPrice price);
  Future<void> deleteSupplierProductPrice(String id);
  Future<void> addOrUpdateExpense(Expense expense);
  Future<void> createAndPostExpensesBulk(List<Expense> expenses);
  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  });
  Future<Expense> editPostedExpense({
    required String expenseId,
    required int expectedVersion,
    String? title,
    String? category,
    double? amount,
    double? originalAmount,
    String? originalCurrency,
    double? exchangeRateAtEntry,
    DateTime? date,
    String? notes,
  });
  Future<void> deleteDraftExpense(String id);
  Future<void> cancelExpense(String id, {String reason = ''});
  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  });
  DeliveryNote? deliveryNoteForSale(String saleId);
  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  });
  Future<void> markDeliveryNoteDelivered(String id);
  Future<void> deleteDeliveryNote(String id);
  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  });
  double? lastPurchasePriceForProduct(String productId);
  int supplierCountForProduct(String productId);
  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  });
  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<void> normalizeRefundAllocations();
  Future<double> refundableSaleCashAmount(String saleId);
  Future<double> refundablePurchaseCashAmount(String purchaseId);
  Future<double> refundablePurchaseReturnCashAmount(String purchaseReturnId);
  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  });
  Future<Sale> createSale({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String discountCurrency = 'USD',
    double discountExchangeRateAtEntry = 0,
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
    String invoiceCurrency = 'USD',
    String paymentCurrency = 'USD',
    double? exchangeRateAtPayment,
    double? paidAmount,
    double? cashReceivedAmount,
    double? paidAmountInPaymentCurrency,
    double? cashReceivedAmountInPaymentCurrency,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  });
  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  });
  Future<Sale> editPostedSale({
    required String saleId,
    required int expectedVersion,
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String? discountCurrency,
    double? discountExchangeRateAtEntry,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  });
  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  });
  Future<void> deleteSaleQuotation(String id);
  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  });
  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  });
  Future<Purchase> updatePurchaseDraft({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  });
  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  });
  Future<void> deleteDraftPurchase(String id);
  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  });
  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  });
  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(
    String productId,
  );
  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  );
  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  });
  PurchaseItem? lastPurchaseItemForProduct(String productId);
  double averagePurchaseCostForProduct(String productId);
  double estimateProfit();
  Future<Purchase?> reloadPurchaseFromSqlite(String id);
  Future<double> refundableExpenseCashAmount(String expenseId);
  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  });
}
