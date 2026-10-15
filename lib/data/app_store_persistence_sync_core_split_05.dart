part of 'app_store.dart';

extension _AppStoreSplitPersistenceSyncCorePart5 on AppStore {
  Future<void> addOrUpdateAccountTransaction(
    AccountTransaction transaction,
  ) async {
    requirePermission(AppPermission.accountingManage);
    final now = DateTime.now();
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      throw ArgumentError(
        'Account transaction accountType must be customer or supplier.',
      );
    }
    if (normalized.accountId.trim().isEmpty) {
      throw ArgumentError('Account transaction accountId is required.');
    }
    if (normalized.debit == 0 && normalized.credit == 0) {
      throw ArgumentError('Account transaction amount is required.');
    }
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        if (previous != null && !previous.isDeleted) {
          await AccountingService.reverseEntryForReference(
            referenceType:
                previous.isCustomer ? 'customer_payment' : 'supplier_payment',
            referenceId: previous.id,
            reason: 'Account payment edited',
            createdBy: _actorName(),
            notifyChange: false,
            withinExistingTransaction: true,
          );
        }
        await _persistAccountTransactionInExistingTransaction(
          sqliteDb,
          synced,
        );
        await AccountingService.recordAccountPayment(
          synced,
          database: sqliteDb,
          withinExistingTransaction: true,
          notifyChange: false,
        );
      });
      _forgetSqliteDirtyBusinessRow(
          AppStore._accountTransactionsKey, synced.id);
      AccountingService.notifyCommittedMutation();
    } else {
      await _persistAccountTransactionSqliteFirst(synced);
      await AccountingService.recordAccountPayment(synced);
    }
    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: index == -1 ? 'upsert' : 'update',
      payload: synced.toJson(),
    );
    await _saveDirty(
      accountTransactions:
          !(LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null),
      sync: true,
    );
    notifyListeners();
  }

  Future<void> deleteAccountTransaction(String id) async {
    requirePermission(AppPermission.accountingManage);
    final index = _accountTransactionIndexForId(id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<AccountTransaction>(
      _accountTransactions[index].copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    final previous = _accountTransactions[index];
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        await AccountingService.reverseEntryForReference(
          referenceType:
              deleted.isCustomer ? 'customer_payment' : 'supplier_payment',
          referenceId: deleted.id,
          reason: 'Account payment deleted',
          createdBy: _actorName(),
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _persistAccountTransactionInExistingTransaction(
          sqliteDb,
          deleted,
        );
      });
      _forgetSqliteDirtyBusinessRow(
        AppStore._accountTransactionsKey,
        deleted.id,
      );
      AccountingService.notifyCommittedMutation();
    } else {
      await _persistAccountTransactionSqliteFirst(deleted);
      await AccountingService.reverseEntryForReference(
        referenceType:
            deleted.isCustomer ? 'customer_payment' : 'supplier_payment',
        referenceId: deleted.id,
        reason: 'Account payment deleted',
        createdBy: _deviceId,
      );
    }
    _putAccountTransactionAtIndex(deleted, index);
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: deleted,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(
      accountTransactions:
          !(LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null),
      sync: true,
    );
    notifyListeners();
  }

  Future<void> _upsertAccountTransactionInternal(
    AccountTransaction transaction,
    DateTime now, {
    String operation = 'upsert',
  }) async {
    final normalized = transaction.copyWith(
      accountType: transaction.accountType.trim().toLowerCase(),
      accountName: transaction.accountName.trim(),
      currency: transaction.currency.trim().isEmpty
          ? 'USD'
          : transaction.currency.trim().toUpperCase(),
      paymentMethod: transaction.paymentMethod.trim(),
      debit: _safeAccountAmount(transaction.debit),
      credit: _safeAccountAmount(transaction.credit),
    );
    if (normalized.accountType != 'customer' &&
        normalized.accountType != 'supplier') {
      return;
    }
    if (normalized.accountId.trim().isEmpty) return;
    if (normalized.debit == 0 && normalized.credit == 0) return;
    final index = _accountTransactionIndexForId(normalized.id);
    final synced = _withSyncMeta<AccountTransaction>(
      normalized,
      now,
      isCreate: index == -1,
    );
    final previous = index == -1 ? null : _accountTransactions[index];

    // Financial account movements are SQLite-first: persist before RAM/UI.
    await _persistAccountTransactionSqliteFirst(synced);

    _putAccountTransactionAtIndex(
      synced,
      index == -1 ? _accountTransactions.length : index,
    );
    _replaceAccountTransactionInLedgerCache(
      previous: previous,
      current: synced,
    );
    _recordSyncChange(
      entityType: 'account_transaction',
      entityId: synced.id,
      operation: operation,
      payload: synced.toJson(),
    );
  }

  Future<void> _recordPurchaseLedger(Purchase purchase, DateTime now) async {
    if (!purchase.isReceived ||
        purchase.isCancelled ||
        purchase.supplierId.trim().isEmpty) {
      return;
    }
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${purchase.id}-purchase-invoice',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: purchase.date,
        type: 'purchaseInvoice',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: 0,
        credit: purchase.subtotal,
        note: 'Purchase invoice ${purchase.purchaseNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'purchase_invoice',
    );
  }

  Future<void> _recordPurchaseCancelLedger(
    Purchase purchase,
    DateTime now, {
    String reason = '',
    bool isReturn = false,
  }) async {
    if (purchase.supplierId.trim().isEmpty) return;
    // Reverse the amounts that were actually posted, rather than rebuilding
    // them from the current Purchase object. A purchase can have been migrated
    // after posting; using its current lines can otherwise create
    // a partial or oversized supplier reversal.
    final invoiceId = '${purchase.id}-purchase-invoice';
    final invoiceIndex = _accountTransactions.indexWhere(
      (transaction) => transaction.id == invoiceId,
    );
    if (invoiceIndex == -1) return;
    final total = _accountTransactions[invoiceIndex].credit;
    if (total <= 0) return;
    final note = reason.trim().isEmpty
        ? (isReturn
            ? 'Purchase return ${purchase.purchaseNo}'
            : 'Purchase cancelled')
        : reason.trim();
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn
            ? '${purchase.id}-purchase-return'
            : '${purchase.id}-purchase-cancel',
        accountType: 'supplier',
        accountId: purchase.supplierId,
        accountName: purchase.supplierName,
        date: now,
        type: isReturn ? 'purchaseReturn' : 'cancel',
        referenceId: purchase.id,
        referenceNo: purchase.purchaseNo,
        debit: total,
        credit: 0,
        note: note,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'purchase_return' : 'purchase_cancel',
    );
  }

  Future<void> _recordSaleLedger(Sale sale, DateTime now) async {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${sale.id}-sale-invoice',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: sale.date,
        type: 'saleInvoice',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: sale.invoiceTotal,
        credit: 0,
        currency: sale.invoiceCurrency,
        note: 'Sale invoice ${sale.invoiceNo}',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'sale_invoice',
    );
  }

  Future<void> _recordSaleCancelLedger(
    Sale sale,
    DateTime now, {
    bool isReturn = false,
    String returnReferenceId = '',
  }) async {
    final accountId = sale.customerId.trim().isNotEmpty
        ? sale.customerId.trim()
        : sale.customerName.trim();
    if (accountId.isEmpty) return;
    final total = sale.invoiceTotal > 0
        ? sale.invoiceTotal
        : ((sale.items.fold<double>(0, (sum, item) => sum + item.lineTotal) -
                sale.discount)
            .clamp(0, double.infinity)
            .toDouble());
    if (total <= 0) return;
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: isReturn
            ? (returnReferenceId.trim().isEmpty
                ? '${sale.id}-sale-return'
                : '${sale.id}-sale-return-${returnReferenceId.trim()}')
            : '${sale.id}-sale-cancel',
        accountType: 'customer',
        accountId: accountId,
        accountName: sale.customerName,
        date: now,
        type: isReturn ? 'saleReturn' : 'cancel',
        referenceId: sale.id,
        referenceNo: sale.invoiceNo,
        debit: 0,
        credit: total,
        currency: sale.invoiceCurrency,
        note: isReturn ? 'Sale return ${sale.invoiceNo}' : 'Sale cancelled',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: isReturn ? 'sale_return' : 'sale_cancel',
    );
  }

  Future<void> _reverseExpenseLedger(Expense expense, DateTime now,
      {String reason = ''}) async {
    final accountId = expense.id.trim();
    if (accountId.isEmpty || expense.amount <= 0) return;
    final accountName =
        expense.title.trim().isEmpty ? 'Expense' : expense.title.trim();
    final currency = expense.originalCurrency.trim().isEmpty
        ? 'USD'
        : expense.originalCurrency.trim().toUpperCase();
    final noteSuffix =
        reason.trim().isEmpty ? 'cancelled expense' : reason.trim();
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-debit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'cancel',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: 0,
        credit: expense.amount,
        currency: currency,
        note: 'Reverse expense debit for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_debit',
    );
    await _upsertAccountTransactionInternal(
      AccountTransaction(
        id: '${expense.id}-expense-credit-reversal',
        accountType: 'supplier',
        accountId: accountId,
        accountName: accountName,
        date: now,
        type: 'paymentReversal',
        paymentMethod: 'Cash',
        referenceId: expense.id,
        referenceNo: accountName,
        debit: expense.amount,
        credit: 0,
        currency: currency,
        note: 'Reverse expense payment for $noteSuffix',
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      now,
      operation: 'expense_reverse_payment',
    );
  }
}
