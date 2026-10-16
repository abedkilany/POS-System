part of 'app_store.dart';

final class _CommerceDomain implements CommerceDomainPort {
  _CommerceDomain(this._store);
  final AppStore _store;

  @override
  List<Customer> get customers => _AppStorePartyRead(_store)._customersReadImpl;
  @override
  List<Customer> get allCustomersForDiagnostics =>
      List<Customer>.unmodifiable(_store._customers);
  @override
  List<Supplier> get suppliers => _AppStorePartyRead(_store)._suppliersReadImpl;
  @override
  List<Sale> get sales => _AppStoreSplitCoreLoading(_store)._salesReadImpl;
  @override
  List<Purchase> get purchases =>
      _AppStoreSplitCoreLoading(_store)._purchasesReadImpl;
  @override
  List<Expense> get expenses =>
      _AppStoreSplitCoreLoading(_store)._expensesReadImpl;
  @override
  int get customersRevision => _store._customersRevision;
  @override
  int get suppliersRevision => _store._suppliersRevision;
  @override
  int get salesRevision => _store._salesRevision;
  @override
  int get salesPageRevision => Object.hashAll(<Object?>[
        _store._productsRevision,
        _store._customersRevision,
        _store._salesRevision,
        _store._deliveryNotesRevision,
        _store._storeProfileRevision,
      ]);
  @override
  double get totalSalesAmount =>
      _AppStoreSplitAccessAuth(_store).totalSalesAmount;
  @override
  int get pendingPurchaseCount => purchasesOverview.pendingPurchaseCount;
  @override
  int get purchasesRevision => _store._purchasesRevision;
  @override
  int get expensesRevision => _store._expensesRevision;
  @override
  PurchasesOverview get purchasesOverview =>
      _AppStorePurchaseInsights(_store)._purchasesOverviewImpl;
  @override
  ExpensesOverview get expensesOverview =>
      _AppStoreSplitSupplierInsights(_store).expensesOverview;
  @override
  double get totalPurchasesAmount => purchasesOverview.totalPurchasesAmount;
  @override
  double get totalExpensesAmount => expensesOverview.totalExpensesAmount;
  @override
  Customer get walkInCustomer => Customer(
        id: AppStore.walkInCustomerId,
        name: AppStore.walkInCustomerName,
        phone: '',
        address: '',
      );
  @override
  List<SaleQuotation> get saleQuotations =>
      _AppStoreSplitCoreLoading(_store).saleQuotations;
  @override
  List<DeliveryNote> get deliveryNotes =>
      _AppStoreSplitCoreLoading(_store).deliveryNotes;
  @override
  List<CreditNote> get creditNotes =>
      List<CreditNote>.unmodifiable(_store._creditNotes);
  @override
  Future<void> ensureCustomersLoaded() => _store._ensureCustomersLoadedImpl();
  @override
  Future<void> ensureSuppliersLoaded() => _store._ensureSuppliersLoadedImpl();
  @override
  Future<void> ensureSalesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureSalesPageDataLoaded();
  @override
  Future<void> ensurePurchasesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensurePurchasesPageDataLoaded();
  @override
  Future<void> ensureQuotationsLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureQuotationsPageDataLoaded();
  @override
  Future<void> ensureDeliveryNotesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureDeliveryNotesPageDataLoaded();
  @override
  Future<void> ensureCreditNotesLoaded() =>
      _AppStoreSplitCoreLoading(_store).ensureCreditNotesLoaded();
  @override
  String resolveCustomerName(String? customerId) =>
      _AppStorePartyRead(_store)._resolveCustomerNameReadImpl(customerId);
  @override
  String sanitizeSelectedCustomerId(String? customerId) =>
      _AppStorePartyRead(_store)._sanitizeSelectedCustomerIdReadImpl(
        customerId,
      );
  @override
  Future<void> addOrUpdateCustomer(Customer customer) =>
      _AppStoreSplitCatalogPartiesExpenses(_store)
          .addOrUpdateCustomer(customer);
  @override
  Future<void> deleteCustomer(String id) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store).deleteCustomer(id);
  @override
  Future<void> addOrUpdateSupplier(Supplier supplier) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store)
          .addOrUpdateSupplier(supplier);
  @override
  Future<void> deleteSupplier(String id) =>
      _AppStoreCatalogPartiesExpensesCatalogParties(_store).deleteSupplier(id);
  @override
  List<SupplierProductPrice> supplierProductPricesForProduct(
    String productId,
  ) =>
      _AppStoreSplitSupplierInsights(_store)
          .supplierProductPricesForProduct(productId);
  @override
  Future<void> addOrUpdateSupplierProductPrice(SupplierProductPrice price) =>
      _AppStoreSplitSupplierInsights(_store)
          .addOrUpdateSupplierProductPrice(price);
  @override
  Future<void> deleteSupplierProductPrice(String id) =>
      _AppStoreSplitSupplierInsights(_store).deleteSupplierProductPrice(id);
  @override
  Future<void> addOrUpdateExpense(Expense expense) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store)
          .addOrUpdateExpense(expense);
  @override
  Future<void> createAndPostExpensesBulk(List<Expense> expenses) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store)
          .createAndPostExpensesBulk(expenses);
  @override
  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  }) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store).postExpense(
        id,
        paidInCash: paidInCash,
        cashPaidAmount: cashPaidAmount,
      );
  @override
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
  }) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store).editPostedExpense(
        expenseId: expenseId,
        expectedVersion: expectedVersion,
        title: title,
        category: category,
        amount: amount,
        originalAmount: originalAmount,
        originalCurrency: originalCurrency,
        exchangeRateAtEntry: exchangeRateAtEntry,
        date: date,
        notes: notes,
      );
  @override
  Future<void> deleteDraftExpense(String id) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store).deleteDraftExpense(id);
  @override
  Future<void> cancelExpense(String id, {String reason = ''}) =>
      _AppStoreCatalogPartiesExpensesExpensePosting(_store)
          .cancelExpense(id, reason: reason);
  @override
  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) =>
      _AppStoreSplitSalesReturns(_store).convertSaleQuotationToSale(
        quotationId,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
      );
  @override
  DeliveryNote? deliveryNoteForSale(String saleId) =>
      _AppStoreSplitSalesReturns(_store).deliveryNoteForSale(saleId);
  @override
  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) =>
      _AppStoreSplitSalesReturns(_store)
          .createDeliveryNoteFromSale(saleId, note: note);
  @override
  Future<void> markDeliveryNoteDelivered(String id) =>
      _AppStoreSplitSalesReturns(_store).markDeliveryNoteDelivered(id);
  @override
  Future<void> deleteDeliveryNote(String id) =>
      _AppStoreSplitSalesReturns(_store).deleteDeliveryNote(id);
  @override
  double? lastPurchasePriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(_store)._lastPurchasePriceForImpl(
        productId: productId,
        supplierId: supplierId,
      );
  @override
  double? lastPurchasePriceForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._lastPurchasePriceForProductImpl(productId);
  @override
  SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStoreSplitSupplierInsights(_store).supplierProductPriceFor(
        productId: productId,
        supplierId: supplierId,
      );
  @override
  int supplierCountForProduct(String productId) =>
      _AppStoreSplitSupplierInsights(_store).supplierCountForProduct(productId);

  @override
  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashSettlement(_store).settleSalePayment(
        saleId: saleId,
        amount: amount,
        discount: discount,
        paymentMethod: paymentMethod,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashSettlement(_store).settlePurchasePayment(
        purchaseId: purchaseId,
        amount: amount,
        discount: discount,
        paymentMethod: paymentMethod,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<void> normalizeRefundAllocations() =>
      _AppStoreWarehouseCashTransfersRefunds(_store).normalizeRefundAllocations();

  @override
  Future<double> refundableSaleCashAmount(String saleId) =>
      _AppStoreWarehouseCashTransfersRefunds(_store).refundableSaleCashAmount(saleId);

  @override
  Future<double> refundablePurchaseCashAmount(String purchaseId) =>
      _AppStoreWarehouseCashTransfersRefunds(_store)
          .refundablePurchaseCashAmount(purchaseId);

  @override
  Future<double> refundablePurchaseReturnCashAmount(String purchaseReturnId) =>
      _AppStoreWarehouseCashTransfersRefunds(_store)
          .refundablePurchaseReturnCashAmount(purchaseReturnId);

  @override
  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashTransfersRefunds(_store).refundSaleCash(
        saleId: saleId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashTransfersRefunds(_store).refundPurchaseCash(
        purchaseId: purchaseId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreWarehouseCashTransfersRefunds(_store).refundPurchaseReturnCash(
        purchaseReturnId: purchaseReturnId,
        amount: amount,
        notes: notes,
        idempotencyKey: idempotencyKey,
        date: date,
      );

  @override
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
  }) =>
      _AppStoreSalesReturnsCreateSale(_store).createSale(
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        originalDiscount: originalDiscount,
        discountCurrency: discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        invoiceCurrency: invoiceCurrency,
        paymentCurrency: paymentCurrency,
        exchangeRateAtPayment: exchangeRateAtPayment,
        paidAmount: paidAmount,
        cashReceivedAmount: cashReceivedAmount,
        paidAmountInPaymentCurrency: paidAmountInPaymentCurrency,
        cashReceivedAmountInPaymentCurrency:
            cashReceivedAmountInPaymentCurrency,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  }) =>
      _AppStoreSalesReturnsCreateReturn(_store).returnSale(
        id,
        restoreStock: restoreStock,
        returnedQuantities: returnedQuantities,
      );

  @override
  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) =>
      _AppStoreSalesReturnsCancelSale(_store).cancelSale(
        id,
        status: status,
        restoreStock: restoreStock,
      );

  @override
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
  }) =>
      _AppStoreSalesReturnsEditSale(_store).editPostedSale(
        saleId: saleId,
        expectedVersion: expectedVersion,
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        originalDiscount: originalDiscount,
        discountCurrency: discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  }) =>
      _AppStoreSalesReturnsEditReturn(_store).editSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
        returnedQuantities: returnedQuantities,
      );

  @override
  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) =>
      _AppStoreSplitSalesReturns(_store).createSaleQuotation(
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        invoiceCurrency: invoiceCurrency,
        note: note,
        validUntil: validUntil,
      );

  @override
  Future<void> deleteSaleQuotation(String id) =>
      _AppStoreSplitSalesReturns(_store).deleteSaleQuotation(id);

  @override
  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  }) =>
      _AppStoreSalesReturnsCancelReturn(_store).cancelSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
      );

  @override
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
  }) =>
      _AppStorePurchasesCreate(_store).createPurchase(
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        receiveNow: receiveNow,
        note: note,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  }) =>
      _AppStorePurchasesReturnCreate(_store).createPurchaseReturn(
        sourcePurchaseId: sourcePurchaseId,
        items: items,
        reason: reason,
      );

  @override
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
  }) =>
      _AppStorePurchasesDraftEdit(_store).updatePurchaseDraft(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  }) =>
      _AppStorePurchasesReceipt(_store).receivePurchase(
        id,
        settleInitialPayment: settleInitialPayment,
        postAccounting: postAccounting,
        batchAllocationsByLine: batchAllocationsByLine,
      );

  @override
  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStorePurchasesReturnEdit(_store).editPurchaseReturn(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  @override
  Future<void> deleteDraftPurchase(String id) =>
      _AppStorePurchasesReceipt(_store).deleteDraftPurchase(id);

  @override
  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  }) =>
      _AppStorePurchasesReversal(_store).returnPurchase(
        id,
        reverseStock: reverseStock,
        reason: reason,
        recordSupplierReturnLedger: recordSupplierReturnLedger,
      );

  @override
  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) =>
      _AppStorePurchasesReversal(_store).cancelPurchase(
        id,
        reverseStock: reverseStock,
        reason: reason,
      );

  @override
  List<SupplierPurchasePrice> purchasePriceHistoryForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(_store)
          ._purchasePriceHistoryForProductImpl(productId);

  @override
  List<SupplierPurchasePrice> supplierPriceComparisonForProduct(
    String productId,
  ) =>
      _AppStorePurchaseInsights(_store)
          ._supplierPriceComparisonForProductImpl(productId);

  @override
  PurchaseItem? lastPurchaseItemFor({
    required String productId,
    required String supplierId,
  }) =>
      _AppStorePurchaseInsights(_store)._lastPurchaseItemForImpl(
        productId: productId,
        supplierId: supplierId,
      );

  @override
  PurchaseItem? lastPurchaseItemForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._lastPurchaseItemForProductImpl(productId);

  @override
  double averagePurchaseCostForProduct(String productId) =>
      _AppStorePurchaseInsights(_store)
          ._averagePurchaseCostForProductImpl(productId);

  @override
  double estimateProfit() =>
      _AppStoreSalesReturnsCancelSale(_store).estimateProfit();

  @override
  Future<Purchase?> reloadPurchaseFromSqlite(String id) =>
      _AppStoreSplitPersistenceSyncCore(_store).reloadPurchaseFromSqlite(id);

  @override
  Future<double> refundableExpenseCashAmount(String expenseId) =>
      _AppStoreWarehouseCashSettlement(_store)
          .refundableExpenseCashAmount(expenseId);

  @override
  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  }) =>
      _AppStoreWarehouseCashSettlement(_store).refundExpenseCash(
        expenseId: expenseId,
        amount: amount,
        notes: notes,
      );
}
