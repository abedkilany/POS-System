part of 'app_store.dart';

extension _AppStoreSplitCatalogPartiesExpensesPart3 on AppStore {
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
  }) async {
    requirePermission(AppPermission.expensesManage);
    final id = expenseId.trim();
    if (id.isEmpty) throw ArgumentError('Expense id is required.');
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Posted expense editing requires SQLite storage.');
    }
    late bool wasCash;
    double? wasCashPaidAmount;
    late Expense edited;
    if (await _expenseByIdFromSqlite(id) == null) {
      throw ArgumentError('Expense not found.');
    }

    await sqliteDb.transaction(() async {
      final pipeline = PostedDocumentEditPipeline<Expense>(
        loadAuthoritative: () async {
          final current = await _expenseByIdFromSqlite(id);
          if (current == null) throw ArgumentError('Expense not found.');
          return current;
        },
        validatePermission: (current) async {
          requirePermission(AppPermission.expensesManage);
          if (!current.isPosted || current.isDeleted) {
            throw StateError('Only active posted expenses can be edited.');
          }
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Expense changed by another user. Reload it before editing.',
            );
          }
        },
        validateDependencies: (current) async {
          final activeCash = await sqliteDb.customSelect(
            '''
            SELECT tx.id, tx.amount
            FROM cash_ledger_transactions tx
            WHERE tx.reference_type = 'expense'
              AND (tx.reference_id = ? OR instr(tx.reference_id, ?) = 1)
              AND tx.reversal_of_id = '' AND tx.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM cash_ledger_transactions rev
                WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(current.id),
              Variable<String>('${current.id}:expense_edit:'),
            ],
          ).getSingleOrNull();
          wasCash = activeCash != null;
          wasCashPaidAmount = (activeCash?.data['amount'] as num?)?.toDouble();
          final settledCredit = await sqliteDb.customSelect(
            '''
            SELECT id FROM cash_operations
            WHERE deleted_at = '' AND status = 'posted'
              AND (
                idempotency_key = ?
                OR idempotency_key LIKE ?
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>('expense-credit-settlement:${current.id}'),
              Variable<String>('expense-credit-settlement:${current.id}:%'),
            ],
          ).getSingleOrNull();
          if (settledCredit != null) {
            throw StateError(
              'A settled credit expense cannot be edited. Reverse its settlement first.',
            );
          }
          final activeRefund = await sqliteDb.customSelect(
            '''
            SELECT tx.id
            FROM cash_ledger_transactions tx
            WHERE tx.reference_type = 'expense_refund'
              AND tx.reference_id LIKE ?
              AND tx.reversal_of_id = '' AND tx.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM cash_ledger_transactions rev
                WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>('${current.id}:%'),
            ],
          ).getSingleOrNull();
          if (activeRefund != null) {
            throw StateError(
              'Expense cannot be edited while a downstream cash refund is active.',
            );
          }
          final nextTitle = title ?? current.title;
          final nextCategory = category ?? current.category;
          final nextAmount = amount ?? current.amount;
          if (nextTitle.trim().isEmpty ||
              nextCategory.trim().isEmpty ||
              !nextAmount.isFinite ||
              nextAmount <= 0) {
            throw ArgumentError('Invalid posted expense values.');
          }
        },
        reverseOperationalEffects: (current) async {
          if (!wasCash) return;
          final reversals = await CashLedgerService(sqliteDb).reverseReference(
            referenceType: 'expense',
            referenceId: current.id,
            reason: 'Expense edited from version ${current.version}',
            createdBy: _actorName(),
            createdByUserId: _activeUser?.id ?? '',
            deviceId: _deviceId,
            occurredAt: DateTime.now().toUtc(),
          );
          if (reversals.isEmpty) {
            throw StateError(
              'Expense Cash Ledger movement is missing; edit was rolled back.',
            );
          }
          final now = DateTime.now().toUtc().toIso8601String();
          await sqliteDb.customUpdate(
            '''
            UPDATE cash_operations
            SET status = 'reversed', reversed_at = ?, reversal_reason = ?,
                reversed_by = ?, reversed_by_user_id = ?, updated_at = ?
            WHERE deleted_at = '' AND status = 'posted'
              AND (idempotency_key = ? OR idempotency_key LIKE ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(
                  'Expense edited from version ${current.version}'),
              Variable<String>(_actorName()),
              Variable<String>(_activeUser?.id ?? ''),
              Variable<String>(now),
              Variable<String>('expense:${current.id}'),
              Variable<String>('expense:${current.id}:expense_edit:%'),
            ],
          );
        },
        reverseAccountingEffects: (current) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'expense',
            referenceId: current.id,
            reason: 'Expense edited from version ${current.version}',
            createdBy: _actorName(),
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _reverseExpenseCompatibilityForEditInTransaction(
            sqliteDb,
            expenseId: current.id,
            reason: 'Expense edited from version ${current.version}',
          );
        },
        applyChanges: (current) async {
          final now = DateTime.now().toUtc();
          final next = current.copyWith(
            title: title ?? current.title,
            category: category ?? current.category,
            amount: amount ?? current.amount,
            originalAmount: originalAmount ?? amount ?? current.originalAmount,
            originalCurrency: originalCurrency ?? current.originalCurrency,
            exchangeRateAtEntry:
                exchangeRateAtEntry ?? current.exchangeRateAtEntry,
            date: (date ?? current.date).toUtc(),
            notes: notes ?? current.notes,
            status: 'Posted',
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            version: current.version + 1,
            lastModifiedByDeviceId: _deviceId,
          );
          final updatedRows = await sqliteDb.customUpdate(
            '''
            UPDATE expenses
            SET title = ?, category = ?, amount = ?, original_amount = ?,
                original_currency = ?, exchange_rate_at_entry = ?, expense_date = ?,
                notes = ?, updated_at = ?, device_id = ?, sync_status = 'pending',
                version = ?, last_modified_by_device_id = ?
            WHERE id = ? AND deleted_at = '' AND expense_status = 'Posted'
              AND version = ?
            ''',
            variables: <Variable<Object>>[
              Variable<String>(next.title.trim()),
              Variable<String>(next.category.trim()),
              Variable<double>(next.amount),
              Variable<double>(next.originalAmount ?? next.amount),
              Variable<String>(next.originalCurrency),
              Variable<double>(next.exchangeRateAtEntry),
              Variable<String>(next.date.toUtc().toIso8601String()),
              Variable<String>(next.notes),
              Variable<String>(now.toIso8601String()),
              Variable<String>(_deviceId),
              Variable<int>(next.version),
              Variable<String>(_deviceId),
              Variable<String>(current.id),
              Variable<int>(expectedVersion),
            ],
          );
          if (updatedRows != 1) {
            throw StateError('Expense changed before edit commit.');
          }
          return next;
        },
        rebuildOperationalEffects: (updated) async => updated,
        buildPostedSnapshot: (updated) async => updated,
        repostAccounting: (updated) async {
          await AccountingService.repostEditedExpenseInExistingTransaction(
            updated,
            paidInCash: wasCash,
            cashPaidAmount: wasCashPaidAmount,
            technicalReferenceId:
                '${updated.id}:expense_edit:v${updated.version}',
          );
        },
        rebuildDerivedState: (updated) async {},
        verifyIntegrity: (updated) async {
          final row = await sqliteDb.customSelect(
            '''
            SELECT version, amount, expense_status
            FROM expenses WHERE id = ? AND deleted_at = '' LIMIT 1
            ''',
            variables: <Variable<Object>>[Variable<String>(updated.id)],
          ).getSingleOrNull();
          if (row == null ||
              (row.data['version'] as num?)?.toInt() != updated.version ||
              row.data['expense_status']?.toString().toLowerCase() !=
                  'posted' ||
              (((row.data['amount'] as num?)?.toDouble() ?? 0) - updated.amount)
                      .abs() >
                  0.000001) {
            throw StateError('Expense edit integrity verification failed.');
          }
          final journal = await sqliteDb.customSelect(
            '''
            SELECT id FROM journal_entries
            WHERE reference_type = 'expense' AND reference_id = ?
              AND deleted_at = '' AND status = 'posted'
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(
                  '${updated.id}:expense_edit:v${updated.version}'),
            ],
          ).getSingleOrNull();
          if (journal == null) {
            throw StateError('Edited expense journal is missing.');
          }
          if (wasCash) {
            final cash = await sqliteDb.customSelect(
              '''
              SELECT tx.id FROM cash_ledger_transactions tx
              WHERE tx.reference_type = 'expense' AND tx.reference_id = ?
                AND tx.reversal_of_id = '' AND tx.deleted_at = ''
                AND NOT EXISTS (
                  SELECT 1 FROM cash_ledger_transactions rev
                  WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
                )
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(
                    '${updated.id}:expense_edit:v${updated.version}'),
              ],
            ).getSingleOrNull();
            if (cash == null) {
              throw StateError(
                  'Edited expense Cash Ledger movement is missing.');
            }
          }
        },
      );
      edited = await pipeline.execute();
    });

    final index = _expenseIndexForId(id);
    if (index >= 0) _expenses[index] = edited;
    _recordSyncChange(
      entityType: 'expense',
      entityId: edited.id,
      operation: 'posted_edit',
      payload: edited.toJson(),
    );
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(expenses: false, accountTransactions: false, sync: true);
    _touchExpensesData();
    notifyListeners();
    return edited;
  }

  Future<void> _reverseExpenseCompatibilityForEditInTransaction(
    VentioDriftDatabase db, {
    required String expenseId,
    required String reason,
  }) async {
    final originals = await db.customSelect(
      '''
      SELECT id, account_type, account_id, account_name, reference_id,
             reference_no, debit, credit, currency, payment_method,
             store_id, branch_id
      FROM account_transactions
      WHERE deleted_at = ''
        AND transaction_type NOT IN ('cancel', 'paymentReversal')
        AND (
          id = ? OR id LIKE ? OR id = ? OR id LIKE ?
          OR id = ? OR id LIKE ?
        )
      ORDER BY transaction_date, created_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>('$expenseId-expense-debit'),
        Variable<String>('$expenseId-expense-debit-edit-v%'),
        Variable<String>('$expenseId-expense-credit'),
        Variable<String>('$expenseId-expense-credit-edit-v%'),
        Variable<String>('$expenseId-expense-credit-payable'),
        Variable<String>('$expenseId-expense-credit-payable-edit-v%'),
      ],
    ).get();
    for (final original in originals) {
      final originalId = original.data['id']?.toString() ?? '';
      if (originalId.isEmpty) continue;
      final reversalId = '$originalId-reversal';
      final already = await db.customSelect(
        "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(reversalId)],
      ).getSingleOrNull();
      if (already != null) continue;
      final nextSort = await db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
          )
          .getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final debit = (original.data['debit'] as num?)?.toDouble() ?? 0.0;
      final credit = (original.data['credit'] as num?)?.toDouble() ?? 0.0;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.customInsert(
        '''
        INSERT INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, account_type,
           account_id, account_name, transaction_date, transaction_type,
           reference_id, reference_no, debit, credit, currency, payment_method,
           note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(reversalId),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(_deviceId),
          Variable<String>(original.data['store_id']?.toString() ?? ''),
          Variable<String>(original.data['branch_id']?.toString() ?? ''),
          Variable<int>(sortIndex),
          Variable<String>(
              original.data['account_type']?.toString() ?? 'supplier'),
          Variable<String>(
              original.data['account_id']?.toString() ?? expenseId),
          Variable<String>(
              original.data['account_name']?.toString() ?? 'Expense'),
          Variable<String>(now),
          Variable<String>(credit > 0 ? 'paymentReversal' : 'cancel'),
          Variable<String>(
              original.data['reference_id']?.toString() ?? expenseId),
          Variable<String>(original.data['reference_no']?.toString() ?? ''),
          Variable<double>(credit),
          Variable<double>(debit),
          Variable<String>(original.data['currency']?.toString() ?? 'USD'),
          Variable<String>(original.data['payment_method']?.toString() ?? ''),
          Variable<String>(reason),
          Variable<String>(_deviceId),
        ],
      );
    }
  }

  Future<void> addOrUpdateExpense(Expense expense) async {
    requirePermission(AppPermission.expensesManage);
    if (expense.title.trim().isEmpty ||
        expense.category.trim().isEmpty ||
        !expense.amount.isFinite ||
        expense.amount <= 0) {
      throw ArgumentError('Invalid expense values.');
    }
    final now = DateTime.now();
    final index = _expenseIndexForId(expense.id);
    final isCreate = index == -1;
    if (!isCreate) {
      final current = _expenses[index];
      if (current.isPosted) {
        throw StateError(
          'Posted expenses cannot be edited. Cancel them first.',
        );
      }
      if (current.isCancelled) {
        throw StateError('Cancelled expenses cannot be edited.');
      }
    }
    final normalized = expense.copyWith(
      status: isCreate ? 'Draft' : expense.status,
    );
    final syncedExpense = _withSyncMeta<Expense>(
      normalized,
      now,
      isCreate: isCreate,
    );
    _putExpenseAtIndex(syncedExpense, isCreate ? _expenses.length : index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: syncedExpense.id,
      operation: isCreate ? 'create' : 'update',
      payload: syncedExpense.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'expenses',
        action: isCreate ? 'create_expense' : 'update_expense',
        message: isCreate
            ? 'Expense created successfully.'
            : 'Expense updated successfully.',
        details:
            'expenseId=${syncedExpense.id} title=${syncedExpense.title} amount=${syncedExpense.amount}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'expense',
        entityId: syncedExpense.id,
        action: isCreate ? 'create' : 'update',
        summary: isCreate ? 'Expense created' : 'Expense updated',
        details: jsonEncode(syncedExpense.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _activeUser?.fullName ?? _activeUser?.username ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'expenses',
        isImportant: true,
      ),
    );
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> postExpense(
    String id, {
    bool paidInCash = true,
    double? cashPaidAmount,
  }) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesApprove,
    });
    final normalizedId = id.trim();
    final index = _expenseIndexForId(normalizedId);
    final expense = index == -1
        ? await _expenseByIdFromSqlite(normalizedId)
        : _expenses[index];
    if (expense == null || expense.isDeleted) {
      throw ArgumentError('Expense not found.');
    }
    if (expense.isPosted || expense.isCancelled) return;
    final now = DateTime.now();
    final candidate = _expenseSyncMetaPreview(
      expense.copyWith(status: 'Posted'),
      now,
    );
    // Phase 5: cash/accounting must succeed before the Expense becomes Posted.
    // The preview above has no dirty-row side effect, so a failure cannot leave
    // a latent Posted row that might be persisted by a later unrelated save.
    if (paidInCash) {
      await AccountingService.recordExpense(
        candidate,
        cashPaidAmount: cashPaidAmount,
      );
    } else {
      await AccountingService.recordExpenseOnCredit(candidate);
    }
    // The posted Expense + accounting + cash + compatibility ledger are already
    // committed atomically. Mirror only when this expense was already resident
    // in AppStore; SQLite remains the authoritative source for paged expenses.
    final posted = candidate;
    if (index != -1) {
      _expenses[index] = posted;
    }
    _recordSyncChange(
      entityType: 'expense',
      entityId: normalizedId,
      operation: 'post',
      payload: posted.toJson(),
    );
    await _saveDirty(expenses: false, accountTransactions: false, sync: true);
    await refreshAccountTransactionsFromSqlite();
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> createAndPostExpensesBulk(List<Expense> expenses) async {
    if (expenses.isEmpty) return;
    requirePermission(AppPermission.expensesManage);
    final section = 'expense.createAndPostBulk';
    final now = DateTime.now();
    final prepared =
        <({Expense source, Expense candidate, int index, bool isCreate})>[];

    // Build side-effect-free Posted previews first. AccountingService commits the
    // complete cash/accounting batch in one SQLite transaction. Only after that
    // succeeds do we mark AppStore rows dirty and expose Posted state.
    for (final expense in expenses) {
      if (expense.title.trim().isEmpty ||
          expense.category.trim().isEmpty ||
          !expense.amount.isFinite ||
          expense.amount <= 0) {
        throw ArgumentError('Invalid expense values.');
      }
      final index = _expenseIndexForId(expense.id);
      if (index != -1) {
        final current = _expenses[index];
        if (current.isPosted) {
          throw StateError(
            'Posted expenses cannot be edited. Cancel them first.',
          );
        }
        if (current.isCancelled) {
          throw StateError('Cancelled expenses cannot be edited.');
        }
      }
      final isCreate = index == -1;
      final source = expense.copyWith(status: 'Posted');
      final candidate = _expenseSyncMetaPreview(
        source,
        now,
        isCreate: isCreate,
      );
      prepared.add((
        source: source,
        candidate: candidate,
        index: index,
        isCreate: isCreate,
      ));
    }

    await AccountingService.recordExpensesBulk(
      prepared.map((item) => item.candidate).toList(growable: false),
    );

    for (final item in prepared) {
      // recordExpensesBulk already persisted this preview atomically.
      final syncedExpense = item.candidate;
      _putExpenseAtIndex(
        syncedExpense,
        item.isCreate ? _expenses.length : item.index,
      );
      _recordSyncChange(
        entityType: 'expense',
        entityId: syncedExpense.id,
        operation: item.isCreate ? 'create' : 'update',
        payload: syncedExpense.toJson(),
      );
      _recordSyncChange(
        entityType: 'expense',
        entityId: syncedExpense.id,
        operation: 'post',
        payload: syncedExpense.toJson(),
      );
    }
    await _traceAsync(
      section,
      'save_dirty',
      () => _saveDirty(
        productDerivedData: false,
        expenses: false,
        accountTransactions: false,
        sync: true,
      ),
      metadata: <String, Object?>{'count': prepared.length},
    );
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> deleteDraftExpense(String id) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesDelete,
    });
    final index = _expenseIndexForId(id);
    if (index == -1) return;
    final expense = _expenses[index];
    if (expense.isPosted) {
      throw StateError('Posted expenses cannot be deleted. Cancel them first.');
    }
    if (expense.isCancelled) {
      throw StateError(
        'Cancelled expenses require permanent delete permission.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Expense>(
      expense.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    _putExpenseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(expenses: true, sync: true);
    _touchExpensesData();
    notifyListeners();
  }

  Future<void> cancelExpense(String id, {String reason = ''}) async {
    requireAnyPermission(<String>{
      AppPermission.expensesManage,
      AppPermission.expensesCancel,
    });
    final index = _expenseIndexForId(id);
    if (index == -1) throw ArgumentError('Expense not found.');
    final expense = _expenses[index];
    if (expense.isCancelled) return;
    if (!expense.isPosted) {
      throw StateError(
        'Only posted expenses can be cancelled. Delete draft expenses instead.',
      );
    }
    final now = DateTime.now();
    final cancelledPreview = expense.copyWith(
      status: 'Cancelled',
      cancelReason: reason.trim(),
      cancelledAt: now,
      cancelledByDeviceId: _deviceId,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (sqliteDb != null) {
      await CashReversalService(sqliteDb).reverseReference(
        referenceType: 'expense',
        referenceId: expense.id,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
        createdBy: _actorName(),
        createdByUserId: _activeUser?.id ?? '',
        deviceId: _deviceId,
        occurredAt: now,
      );
    } else {
      await AccountingService.reverseEntryForReference(
        referenceType: 'expense',
        referenceId: expense.id,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
        createdBy: _deviceId,
      );
    }
    final cancelled = sqliteDb != null
        ? _expenseSyncMetaPreview(cancelledPreview, now)
        : _withSyncMeta<Expense>(cancelledPreview, now);
    _putExpenseAtIndex(cancelled, index);
    if (sqliteDb == null) {
      await _reverseExpenseLedger(
        cancelled,
        now,
        reason: reason.trim().isEmpty ? 'Expense cancelled' : reason.trim(),
      );
    }
    _recordSyncChange(
      entityType: 'expense',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _saveDirty(
      expenses: sqliteDb == null,
      accountTransactions: sqliteDb == null,
      sync: true,
    );
    _touchExpensesData();
    notifyListeners();
  }
}
