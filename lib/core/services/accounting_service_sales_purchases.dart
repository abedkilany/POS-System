part of 'accounting_service_impl.dart';

Future<void> recordSale(
  Sale sale, {
  String? accountingReferenceId,
  bool paymentPostedSeparately = false,
  bool withinExistingTransaction = false,
}) async {
  if (sale.isDeleted || sale.isCancelled) return;
  if (!isAvailable) return;
  _requireSalePostedSnapshotMatches(
    sale,
    validatePaymentTotals: !paymentPostedSeparately,
  );
  final accountsReceivable = await resolveAccountRole('accounts_receivable');
  final salesRevenue = await resolveAccountRole('sales_revenue');
  final salesDiscounts = await resolveAccountRole('sales_discounts');
  final salesTax = await resolveAccountRole('sales_tax');
  final cogsAccount = await resolveAccountRole('cogs');
  final accountingCurrency = sale.invoiceCurrency.trim().isEmpty
      ? _moneyProfile.baseCurrency
      : sale.invoiceCurrency.trim().toUpperCase();
  final rawInvoiceTotal = _cleanAmount(sale.invoiceTotal);
  final rawSaleTotal = _cleanAmount(sale.total);
  final rawGrossSubtotal = _cleanAmount(sale.subtotal);
  final rawDiscount = min(
    rawGrossSubtotal,
    _cleanAmount(sale.discount),
  );
  final saleTotal = _roundMoney(rawSaleTotal, currency: accountingCurrency);
  final grossSubtotal =
      _roundMoney(rawGrossSubtotal, currency: accountingCurrency);
  final discountGross = _roundMoney(rawDiscount, currency: accountingCurrency);
  final frozenTax = _snapshotTaxBreakdown(
    sale.postedSnapshot,
    currency: accountingCurrency,
  );
  final legacyGrossTax =
      frozenTax == null ? await _taxBreakdown(grossSubtotal) : null;
  final legacyNetSaleTax =
      frozenTax == null ? await _taxBreakdown(saleTotal) : null;
  final revenueBeforeDiscount =
      frozenTax?.grossNetBeforeDiscount ?? legacyGrossTax!.netAmount;
  final finalNetRevenue = frozenTax?.netAmount ?? legacyNetSaleTax!.netAmount;
  final salesDiscountNet = discountGross <= 0
      ? 0.0
      : max(
          0.0,
          _roundMoney(
            revenueBeforeDiscount - finalNetRevenue,
            currency: accountingCurrency,
          ),
        );
  // Phase 2: posted documents own their frozen, line-level VAT facts. This
  // prevents a later tax-profile/rate change from rewriting the accounting
  // meaning of an already-posted invoice. Legacy documents without the v2
  // tax snapshot keep the historical global-rate fallback.
  final outputTax = frozenTax?.taxAmount ?? legacyNetSaleTax!.taxAmount;
  final paidInInvoiceCurrency =
      _cleanAmount(sale.paidAmount.clamp(0, rawInvoiceTotal).toDouble());
  final rawPaid = rawInvoiceTotal <= 0
      ? 0.0
      : rawSaleTotal * (paidInInvoiceCurrency / rawInvoiceTotal);
  final paid = paymentPostedSeparately
      ? 0.0
      : min(
          saleTotal,
          _roundMoney(_cleanAmount(rawPaid), currency: accountingCurrency),
        );
  final balance =
      _roundMoney(_cleanAmount(saleTotal - paid), currency: accountingCurrency);
  final cogs = _roundMoney(
    _cleanAmount(
        sale.items.fold<double>(0, (sum, item) => sum + item.lineCost)),
    currency: accountingCurrency,
  );
  // A free/sample sale can have zero revenue but still carry inventory cost.
  // In that case the COGS/Inventory journal is mandatory. Only skip when
  // there is neither a financial sale amount nor an inventory cost effect.
  if (grossSubtotal <= 0 && cogs <= 0) return;
  final lines = <JournalLineDraft>[];

  final isCashSalePayment =
      paid > 0 && _isCashPaymentMethod(sale.paymentMethod);
  final cashSaleLocation = isCashSalePayment
      ? await _openCashDrawerLocationForDevice(
          deviceId: sale.deviceId, branchId: sale.branchId)
      : null;
  if (isCashSalePayment && cashSaleLocation == null) {
    throw StateError(
        'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل قبول الدفع النقدي.');
  }
  if (paid > 0) {
    lines.add(JournalLineDraft(
      accountId: cashSaleLocation?.accountId ??
          await _paymentAccountId(sale.paymentMethod),
      debit: paid,
      credit: 0,
      memo: 'دفعة مستلمة للمبيعة ${sale.invoiceNo}',
      partyType: 'customer',
      partyId: sale.customerId,
      partyName: sale.customerName,
    ));
  }
  if (balance > 0) {
    lines.add(JournalLineDraft(
      accountId: accountsReceivable,
      debit: balance,
      credit: 0,
      memo: 'مبلغ مستحق على العميل للمبيعة ${sale.invoiceNo}',
      partyType: 'customer',
      partyId: sale.customerId,
      partyName: sale.customerName,
    ));
  }
  if (revenueBeforeDiscount > 0) {
    lines.add(JournalLineDraft(
      accountId: salesRevenue,
      debit: 0,
      credit: revenueBeforeDiscount,
      memo: outputTax > 0
          ? 'إيرادات المبيعات قبل الخصم والضريبة ${sale.invoiceNo}'
          : 'إيرادات المبيعات قبل الخصم ${sale.invoiceNo}',
    ));
  }
  if (salesDiscountNet > 0) {
    lines.add(JournalLineDraft(
      accountId: salesDiscounts,
      debit: salesDiscountNet,
      credit: 0,
      memo: 'خصم مبيعات ${sale.invoiceNo}',
    ));
  }
  if (outputTax > 0) {
    lines.add(JournalLineDraft(
      accountId: salesTax,
      debit: 0,
      credit: outputTax,
      memo: 'ضريبة المخرجات بعد الخصم ${sale.invoiceNo}',
    ));
  }
  if (cogs > 0) {
    final inventoryCredits = await _inventoryAmountsByAccount(
      _db,
      <_InventoryAmount>[
        for (final item in sale.items)
          _InventoryAmount(item.productId, item.lineCost),
      ],
      targetAmount: cogs,
    );
    lines.add(JournalLineDraft(
      accountId: cogsAccount,
      debit: cogs,
      credit: 0,
      memo: 'تكلفة البضاعة المباعة ${sale.invoiceNo}',
    ));
    for (final inventory in inventoryCredits.entries) {
      lines.add(JournalLineDraft(
        accountId: inventory.key,
        debit: 0,
        credit: inventory.value,
        memo: 'مخزون صادر للمبيعة ${sale.invoiceNo}',
      ));
    }
  }
  final entryId = await createPostedEntry(
    JournalEntryDraft(
      entryDate: sale.date,
      referenceType: 'sale',
      referenceId: accountingReferenceId?.trim().isNotEmpty == true
          ? accountingReferenceId!.trim()
          : sale.id,
      referenceNo: sale.invoiceNo,
      description: 'فاتورة مبيعات ${sale.invoiceNo}',
      createdBy: sale.lastModifiedByDeviceId,
      storeId: sale.storeId,
      branchId: sale.branchId,
      lines: lines,
    ),
    database: _db,
    withinExistingTransaction: withinExistingTransaction,
  );
  if (entryId.isNotEmpty && cashSaleLocation != null && paid > 0) {
    await _moveCashLocationBalance(cashSaleLocation.id, paid, sale.date);
  }
}

Future<String> recordSaleReturn({
  required Sale sale,
  required String returnReferenceId,
  required DateTime date,
  required double returnAmount,
  required double returnCogs,
  List<SaleItem> returnedItems = const <SaleItem>[],
  PostedDocumentSnapshot? returnSnapshot,
  String createdBy = '',
  bool withinExistingTransaction = false,
}) async {
  if (!isAvailable ||
      returnReferenceId.trim().isEmpty ||
      (returnAmount <= 0 && returnCogs <= 0)) {
    return '';
  }
  final salesReturns = await resolveAccountRole('sales_returns');
  final salesTax = await resolveAccountRole('sales_tax');
  final accountsReceivable = await resolveAccountRole('accounts_receivable');
  final cogsAccount = await resolveAccountRole('cogs');
  final accountingCurrency = sale.invoiceCurrency.trim().isEmpty
      ? _moneyProfile.baseCurrency
      : sale.invoiceCurrency.trim().toUpperCase();
  final gross = _roundMoney(
    _cleanAmount(returnAmount),
    currency: accountingCurrency,
  );
  final cogs = _roundMoney(
    _cleanAmount(returnCogs),
    currency: accountingCurrency,
  );
  final frozenReturnTax = _snapshotTaxBreakdown(
    returnSnapshot,
    currency: accountingCurrency,
  );
  final tax = frozenReturnTax == null ? await _taxBreakdown(gross) : null;
  // Historical invoices can contain line-level discount rounding that is
  // one minor unit away from the proportional discount used for the return.
  // The credit line is authoritative, so derive the net debit from the
  // rounded gross after preserving the frozen tax amount. This keeps the
  // journal balanced without changing the return amount shown to the user.
  final returnTaxAmount = _roundMoney(
    (frozenReturnTax?.taxAmount ?? tax!.taxAmount).clamp(0, gross).toDouble(),
    currency: accountingCurrency,
  );
  final returnNet = _roundMoney(
    (gross - returnTaxAmount).clamp(0, double.infinity).toDouble(),
    currency: accountingCurrency,
  );
  final lines = <JournalLineDraft>[];
  if (gross > 0) {
    lines.add(JournalLineDraft(
      accountId: salesReturns,
      debit: returnNet,
      credit: 0,
      memo: 'مرتجع مبيعات ${sale.invoiceNo}',
    ));
    if (returnTaxAmount > 0) {
      lines.add(JournalLineDraft(
        accountId: salesTax,
        debit: returnTaxAmount,
        credit: 0,
        memo: 'عكس ضريبة مبيعات ${sale.invoiceNo}',
      ));
    }
    lines.add(JournalLineDraft(
      accountId: accountsReceivable,
      debit: 0,
      credit: gross,
      memo: 'رصيد دائن للعميل عن مرتجع ${sale.invoiceNo}',
      partyType: 'customer',
      partyId: sale.customerId,
      partyName: sale.customerName,
    ));
  }
  if (cogs > 0) {
    final sourceItems = returnedItems.isEmpty ? sale.items : returnedItems;
    final inventoryDebits = await _inventoryAmountsByAccount(
      _db,
      <_InventoryAmount>[
        for (final item in sourceItems)
          _InventoryAmount(item.productId, item.lineCost),
      ],
      targetAmount: cogs,
    );
    for (final inventory in inventoryDebits.entries) {
      lines.add(JournalLineDraft(
        accountId: inventory.key,
        debit: inventory.value,
        credit: 0,
        memo: 'إعادة مخزون مرتجع ${sale.invoiceNo}',
      ));
    }
    lines.add(JournalLineDraft(
      accountId: cogsAccount,
      debit: 0,
      credit: cogs,
      memo: 'عكس تكلفة بضاعة مباعة ${sale.invoiceNo}',
    ));
  }
  return createPostedEntry(
    JournalEntryDraft(
      entryDate: date,
      referenceType: 'sale_return',
      referenceId: returnReferenceId.trim(),
      referenceNo: sale.invoiceNo,
      description: 'مرتجع مبيعات ${sale.invoiceNo}',
      source: 'system',
      createdBy: createdBy.trim().isEmpty
          ? sale.lastModifiedByDeviceId
          : createdBy.trim(),
      storeId: sale.storeId,
      branchId: sale.branchId,
      lines: lines,
    ),
    database: _db,
    withinExistingTransaction: withinExistingTransaction,
  );
}

Future<bool> recordPurchase(Purchase purchase,
    {String accountingReferenceId = '',
    bool paymentPostedSeparately = false,
    bool withinExistingTransaction = false}) async {
  if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0) {
    return true;
  }
  if (!isAvailable) return true;
  _requirePurchasePostedSnapshotMatches(
    purchase,
    validatePaymentTotals: !paymentPostedSeparately,
  );
  final purchaseTax = await resolveAccountRole('purchase_tax');
  final accountsPayable = await resolveAccountRole('accounts_payable');
  final accountingCurrency = _moneyProfile.baseCurrency;
  final rawTotal = _cleanAmount(purchase.subtotal);
  final total = _roundMoney(rawTotal, currency: accountingCurrency);
  final frozenPurchaseTax = _snapshotTaxBreakdown(
    purchase.postedSnapshot,
    currency: accountingCurrency,
  );
  final legacyPurchaseTax =
      frozenPurchaseTax == null ? await _taxBreakdown(total) : null;
  final purchaseNet =
      frozenPurchaseTax?.netAmount ?? legacyPurchaseTax!.netAmount;
  final inputTax = frozenPurchaseTax?.taxAmount ?? legacyPurchaseTax!.taxAmount;
  final paid = paymentPostedSeparately
      ? 0.0
      : min(
          total,
          _roundMoney(
            _cleanAmount(purchase.paidAmount.clamp(0, rawTotal).toDouble()),
            currency: accountingCurrency,
          ),
        );
  final balance =
      _roundMoney(_cleanAmount(total - paid), currency: accountingCurrency);
  final lines = <JournalLineDraft>[];
  final purchaseSnapshot = purchase.postedSnapshot;
  final hasFrozenPurchaseTax = purchaseSnapshot != null &&
      !purchaseSnapshot.legacyBackfill &&
      purchaseSnapshot.currency.taxSchemaVersion >= 2 &&
      purchaseSnapshot.lines.length == purchase.items.length;
  final inventoryDebits = await _inventoryAmountsByAccount(
    _db,
    <_InventoryAmount>[
      for (var index = 0; index < purchase.items.length; index += 1)
        _InventoryAmount(
          purchase.items[index].productId,
          hasFrozenPurchaseTax
              ? purchaseSnapshot.lines[index].taxableBase
              : purchase.items[index].lineTotal,
        ),
    ],
    targetAmount: purchaseNet,
  );
  for (final inventory in inventoryDebits.entries) {
    lines.add(JournalLineDraft(
      accountId: inventory.key,
      debit: inventory.value,
      credit: 0,
      memo: inputTax > 0
          ? 'مخزون مستلم قبل الضريبة ${purchase.purchaseNo}'
          : 'مخزون مستلم من المشتريات ${purchase.purchaseNo}',
      partyType: 'supplier',
      partyId: purchase.supplierId,
      partyName: purchase.supplierName,
    ));
  }
  if (inputTax > 0) {
    lines.add(JournalLineDraft(
      accountId: purchaseTax,
      debit: inputTax,
      credit: 0,
      memo: 'ضريبة المدخلات / ضريبة المشتريات ${purchase.purchaseNo}',
      partyType: 'supplier',
      partyId: purchase.supplierId,
      partyName: purchase.supplierName,
    ));
  }
  final isCashPurchasePayment =
      paid > 0 && _isCashPaymentMethod(purchase.paymentMethod);
  final cashPurchaseLocation = isCashPurchasePayment
      ? await _openCashDrawerLocationForDevice(
          deviceId: purchase.deviceId, branchId: purchase.branchId)
      : null;
  if (isCashPurchasePayment && cashPurchaseLocation == null) {
    throw StateError(
        'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل دفع نقدي.');
  }
  if (paid > 0) {
    lines.add(JournalLineDraft(
      accountId: cashPurchaseLocation?.accountId ??
          await _paymentAccountId(purchase.paymentMethod),
      debit: 0,
      credit: paid,
      memo: 'دفعة مدفوعة للمشتريات ${purchase.purchaseNo}',
      partyType: 'supplier',
      partyId: purchase.supplierId,
      partyName: purchase.supplierName,
    ));
  }
  if (balance > 0) {
    lines.add(JournalLineDraft(
      accountId: accountsPayable,
      debit: 0,
      credit: balance,
      memo: 'مبلغ مستحق للمورد عن المشتريات ${purchase.purchaseNo}',
      partyType: 'supplier',
      partyId: purchase.supplierId,
      partyName: purchase.supplierName,
    ));
  }
  final referenceId = accountingReferenceId.trim().isEmpty
      ? purchase.id
      : accountingReferenceId.trim();
  final entryId = await createPostedEntry(
    JournalEntryDraft(
      entryDate: purchase.date,
      referenceType: 'purchase',
      referenceId: referenceId,
      referenceNo: purchase.purchaseNo,
      description: 'فاتورة مشتريات ${purchase.purchaseNo}',
      createdBy: purchase.lastModifiedByDeviceId,
      storeId: purchase.storeId,
      branchId: purchase.branchId,
      lines: lines,
    ),
    database: _db,
    withinExistingTransaction: withinExistingTransaction,
  );
  if (entryId.isNotEmpty && cashPurchaseLocation != null && paid > 0) {
    await _moveCashLocationBalance(
        cashPurchaseLocation.id, -paid, purchase.date);
  }
  return entryId.isNotEmpty;
}

/// Validates cash prerequisites before a purchase is persisted. Cash
/// purchases must not be allowed to create stock or supplier-ledger rows
/// when there is no open drawer to receive the matching cash movement.
Future<void> validatePurchasePayment({
  required String paymentMethod,
  required double paidAmount,
  required String deviceId,
  required String branchId,
}) async {
  if (!isAvailable || paidAmount <= 0 || !_isCashPaymentMethod(paymentMethod)) {
    return;
  }
  final drawer = await _openCashDrawerLocationForDevice(
    deviceId: deviceId,
    branchId: branchId,
  );
  if (drawer == null) {
    throw StateError(
        'لا توجد وردية نقدية مفتوحة لدرج هذا الجهاز. افتح وردية قبل تسجيل دفع نقدي.');
  }
  await ensureCashOutflowAllowed(
    cashLocationId: drawer.id,
    amount: paidAmount,
    database: _db,
  );
}

String _expenseAccountRoleKey(Expense expense) {
  String normalize(String value) => value.trim().toLowerCase();

  final type = normalize(expense.title);
  final category = normalize(expense.category);

  const aliases = <String, String>{
    'rent': 'rent_expense',
    'إيجار': 'rent_expense',
    'ايجار': 'rent_expense',
    'electricity': 'electricity_expense',
    'كهرباء': 'electricity_expense',
    'water': 'water_expense',
    'مياه': 'water_expense',
    'internet': 'telecom_expense',
    'phone': 'telecom_expense',
    'telephone': 'telecom_expense',
    'telecom': 'telecom_expense',
    'إنترنت': 'telecom_expense',
    'انترنت': 'telecom_expense',
    'هاتف': 'telecom_expense',
    'salaries': 'payroll_expense',
    'salary': 'payroll_expense',
    'wages': 'payroll_expense',
    'bonuses': 'payroll_expense',
    'bonus': 'payroll_expense',
    'رواتب': 'payroll_expense',
    'أجور': 'payroll_expense',
    'اجور': 'payroll_expense',
    'مكافآت': 'payroll_expense',
    'مكافات': 'payroll_expense',
    'fuel': 'transport_expense',
    'transportation': 'transport_expense',
    'transport': 'transport_expense',
    'delivery': 'transport_expense',
    'وقود': 'transport_expense',
    'مواصلات': 'transport_expense',
    'نقل': 'transport_expense',
    'توصيل': 'transport_expense',
    'maintenance': 'maintenance_expense',
    'صيانة': 'maintenance_expense',
    'advertising': 'marketing_expense',
    'design': 'marketing_expense',
    'social media': 'marketing_expense',
    'promotions': 'marketing_expense',
    'marketing': 'marketing_expense',
    'إعلانات': 'marketing_expense',
    'اعلانات': 'marketing_expense',
    'تصميم': 'marketing_expense',
    'تواصل اجتماعي': 'marketing_expense',
    'عروض ترويجية': 'marketing_expense',
    'تسويق': 'marketing_expense',
    'stationery': 'office_expense',
    'printing': 'office_expense',
    'cleaning': 'office_expense',
    'supplies': 'office_expense',
    'packaging': 'office_expense',
    'furniture': 'office_expense',
    'قرطاسية': 'office_expense',
    'طباعة': 'office_expense',
    'تنظيف': 'office_expense',
    'مستلزمات': 'office_expense',
    'تغليف': 'office_expense',
    'أثاث': 'office_expense',
    'اثاث': 'office_expense',
    'bank fees': 'bank_fees',
    'bank fee': 'bank_fees',
    'رسوم بنكية': 'bank_fees',
  };

  final direct = aliases[type];
  if (direct != null) return direct;

  // Category fallbacks intentionally remain conservative. Only categories
  // where every custom subtype belongs to the same accounting family are
  // routed automatically. Unknown/legacy values stay on general_expense.
  if (category == 'marketing' || category == 'تسويق') {
    return 'marketing_expense';
  }
  if (category == 'vehicles' || category == 'مركبات') {
    return 'transport_expense';
  }
  if (category == 'office' || category == 'مكتب') {
    return 'office_expense';
  }
  return 'general_expense';
}
