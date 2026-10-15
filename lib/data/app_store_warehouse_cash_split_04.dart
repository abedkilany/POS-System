part of 'app_store.dart';

extension _AppStoreSplitWarehouseCashPart4 on AppStore {
  Future<double> refundableExpenseCashAmount(String expenseId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final expense = _expenses.where((item) => item.id == expenseId).firstOrNull;
    if (expense == null || expense.isDeleted || !expense.isPosted) return 0;
    final service = PaymentVoucherService(sqliteDb);
    final paid = await service.cashPaidForExpense(expense.id);
    final overpayment = max(0.0, paid - expense.amount);
    return service.refundableCashForExpense(
      expense.id,
      maxRefundAmount: overpayment,
    );
  }

  Future<double> refundExpenseCash({
    required String expenseId,
    double? amount,
    String notes = '',
  }) async {
    requirePermission(AppPermission.expensesManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final expense = _expenses.where((item) => item.id == expenseId).firstOrNull;
    if (expense == null || expense.isDeleted || !expense.isPosted) {
      throw StateError('Only posted expenses can be refunded.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final paid = await service.cashPaidForExpense(expense.id);
    final overpayment = max(0.0, paid - expense.amount);
    final available = await service.refundableCashForExpense(
      expense.id,
      maxRefundAmount: overpayment,
    );
    final requested = amount ?? available;
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final context = await _openCashVoucherContext();
    final refunded = await PaymentVoucherService(sqliteDb).refundExpenseCash(
      expenseId: expense.id,
      expenseTitle: expense.title,
      requestedAmount: min(requested, available),
      maxRefundAmount: overpayment,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      currency: storeProfile.baseCurrency,
      notes: notes.trim().isEmpty
          ? 'Cash refund for ${expense.title}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      refundKey: 'manual:${DateTime.now().microsecondsSinceEpoch}',
    );
    if (refunded > 0.000001) await refreshAccountTransactionsFromSqlite();
    return refunded;
  }

  Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    final type = accountType.trim().toLowerCase();
    if (type != 'customer' && type != 'supplier') {
      throw ArgumentError('Account type must be customer or supplier.');
    }
    if (!amount.isFinite ||
        amount < 0 ||
        !discount.isFinite ||
        discount < 0 ||
        amount + discount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    if (type == 'customer') {
      requirePermission(AppPermission.customersPaymentManage);
    } else {
      requirePermission(AppPermission.suppliersPaymentManage);
    }

    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }

    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Account payments require the SQLite authoritative store.');
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'account:$type:${accountId.trim()}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    final service = PaymentVoucherService(sqliteDb);

    if (type == 'customer') {
      await service.createReceipt(
        customerId: accountId.trim(),
        customerName: accountName.trim(),
        amount: amount,
        discount: discount,
        currency: storeProfile.baseCurrency,
        paymentMethod: method,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        storeId: appIdentity.storeId,
        idempotencyKey: key,
        date: when,
      );
    } else {
      await service.createPayment(
        supplierId: accountId.trim(),
        supplierName: accountName.trim(),
        amount: amount,
        discount: discount,
        currency: storeProfile.baseCurrency,
        paymentMethod: method,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        storeId: appIdentity.storeId,
        idempotencyKey: key,
        date: when,
      );
    }

    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
  }

  Future<ReceiptVoucher> editReceiptVoucher({
    required String voucherId,
    required int expectedVersion,
    String? customerId,
    String? customerName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) async {
    requirePermission(AppPermission.customersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Receipt editing requires the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final current = await service.findReceiptById(voucherId);
    if (current == null) throw ArgumentError('Receipt voucher not found.');
    final method = paymentMethod?.trim().isNotEmpty == true
        ? paymentMethod!.trim()
        : current.paymentMethod;
    var resolvedLocationId = cashLocationId ?? current.cashLocationId;
    var resolvedSessionId = cashDrawerSessionId ?? current.cashDrawerSessionId;
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      if ((cashLocationId ?? '').trim().isEmpty ||
          (cashDrawerSessionId ?? '').trim().isEmpty) {
        final context = await _openCashVoucherContext();
        resolvedLocationId = context['cashLocationId'] ?? '';
        resolvedSessionId = context['sessionId'] ?? '';
      }
    }
    final edited = await service.editReceipt(
      voucherId: voucherId,
      expectedVersion: expectedVersion,
      customerId: customerId,
      customerName: customerName,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      cashLocationId: resolvedLocationId,
      cashDrawerSessionId: resolvedSessionId,
      allocations: allocations,
      notes: notes,
      date: date,
      editedBy: _actorName(),
      editedByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return edited;
  }

  Future<PaymentVoucher> editPaymentVoucher({
    required String voucherId,
    required int expectedVersion,
    String? supplierId,
    String? supplierName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Payment editing requires the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final current = await service.findPaymentById(voucherId);
    if (current == null) throw ArgumentError('Payment voucher not found.');
    final method = paymentMethod?.trim().isNotEmpty == true
        ? paymentMethod!.trim()
        : current.paymentMethod;
    var resolvedLocationId = cashLocationId ?? current.cashLocationId;
    var resolvedSessionId = cashDrawerSessionId ?? current.cashDrawerSessionId;
    if (method.toLowerCase() == 'cash') {
      requirePermission(AppPermission.cashBoxManage);
      if ((cashLocationId ?? '').trim().isEmpty ||
          (cashDrawerSessionId ?? '').trim().isEmpty) {
        final context = await _openCashVoucherContext();
        resolvedLocationId = context['cashLocationId'] ?? '';
        resolvedSessionId = context['sessionId'] ?? '';
      }
    }
    final edited = await service.editPayment(
      voucherId: voucherId,
      expectedVersion: expectedVersion,
      supplierId: supplierId,
      supplierName: supplierName,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      cashLocationId: resolvedLocationId,
      cashDrawerSessionId: resolvedSessionId,
      allocations: allocations,
      notes: notes,
      date: date,
      editedBy: _actorName(),
      editedByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return edited;
  }

  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.customersPaymentManage);
    return _settleSalePaymentInternal(
      saleId: saleId,
      amount: amount,
      discount: discount,
      paymentMethod: paymentMethod,
      notes: notes,
      idempotencyKey: idempotencyKey,
      date: date,
    );
  }

  Future<Sale> _settleSalePaymentInternal({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    if (!amount.isFinite ||
        amount < 0 ||
        !discount.isFinite ||
        discount < 0 ||
        amount + discount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Sale settlement requires the SQLite authoritative store.');
    }
    final current = await _saleByIdFromSqlite(saleId);
    if (current == null || current.isCancelled) {
      throw StateError('Sale is not available for payment.');
    }
    if (amount + discount > current.balanceDue + 0.000001) {
      throw StateError('Payment exceeds the remaining sale balance.');
    }
    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'sale:${current.id}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    await PaymentVoucherService(sqliteDb).createReceipt(
      customerId: current.customerId,
      customerName: current.customerName,
      amount: amount,
      discount: discount,
      currency: current.invoiceCurrency,
      paymentMethod: method,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      allocations: <PaymentAllocationDraft>[
        PaymentAllocationDraft(
          referenceId: current.id,
          referenceNumber: current.invoiceNo,
          amount: amount,
          referenceAmount: amount + discount,
          referenceCurrency: current.invoiceCurrency,
          exchangeRate: 1,
        ),
      ],
      notes: notes,
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      idempotencyKey: key,
      date: when,
    );
    await refreshAccountTransactionsFromSqlite();
    final updated = await _saleByIdFromSqlite(current.id);
    if (updated == null) throw StateError('Sale payment cache refresh failed.');
    final index = _sales.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _sales[index] = updated;
    _recordSyncChange(
      entityType: 'sale',
      entityId: updated.id,
      operation: 'payment_cache_update',
      payload: updated.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    notifyListeners();
    return updated;
  }

  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    if (!amount.isFinite ||
        amount < 0 ||
        !discount.isFinite ||
        discount < 0 ||
        amount + discount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Purchase settlement requires the SQLite authoritative store.');
    }
    final current = await _purchaseByIdFromSqlite(purchaseId);
    if (current == null || current.isCancelled || !current.isReceived) {
      throw StateError('Purchase is not available for payment.');
    }
    if (current.isPurchaseReturn) {
      throw StateError(
          'Purchase returns are settled through the purchase return refund action.');
    }
    if (amount + discount > current.balanceDue + 0.000001) {
      throw StateError('Payment exceeds the remaining purchase balance.');
    }
    final method = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    var cashLocationId = '';
    var cashDrawerSessionId = '';
    if (method.toLowerCase() == 'cash') {
      final context = await _openCashVoucherContext();
      cashLocationId = context['cashLocationId'] ?? '';
      cashDrawerSessionId = context['sessionId'] ?? '';
    }
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim().isNotEmpty
        ? idempotencyKey.trim()
        : 'purchase:${current.id}:payment:${when.microsecondsSinceEpoch}:$_deviceId';
    await PaymentVoucherService(sqliteDb).createPayment(
      supplierId: current.supplierId,
      supplierName: current.supplierName,
      amount: amount,
      discount: discount,
      currency: storeProfile.baseCurrency,
      paymentMethod: method,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      allocations: <PaymentAllocationDraft>[
        PaymentAllocationDraft(
          referenceId: current.id,
          referenceNumber: current.purchaseNo,
          amount: amount,
          referenceAmount: amount + discount,
          referenceCurrency: storeProfile.baseCurrency,
          exchangeRate: 1,
        ),
      ],
      notes: notes,
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      idempotencyKey: key,
      date: when,
    );
    await refreshAccountTransactionsFromSqlite();
    final updated = await _purchaseByIdFromSqlite(current.id);
    if (updated == null) {
      throw StateError('Purchase payment cache refresh failed.');
    }
    final index = _purchaseIndexForId(updated.id);
    if (index >= 0) _putPurchaseAtIndex(updated, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: updated.id,
      operation: 'payment_cache_update',
      payload: updated.toJson(),
    );
    await _saveDirty(accountTransactions: true, sync: true);
    _touchPurchasesData();
    notifyListeners();
    return updated;
  }

  PurchaseItem _copyPurchaseItemWith({
    required PurchaseItem item,
    String? lineId,
    List<BatchAllocation>? batchAllocations,
  }) {
    return PurchaseItem(
      lineId: lineId ?? item.lineId,
      sourceLineId: item.sourceLineId,
      productId: item.productId,
      productName: item.productName,
      quantity: item.quantity,
      unitCost: item.unitCost,
      purchaseUnitId: item.purchaseUnitId,
      purchaseUnitName: item.purchaseUnitName,
      conversionToBase: item.conversionToBase,
      originalUnitCost: item.originalUnitCost,
      unitCostCurrency: item.unitCostCurrency,
      exchangeRateAtEntry: item.exchangeRateAtEntry,
      batchAllocations: batchAllocations ?? item.batchAllocations,
    );
  }
}
