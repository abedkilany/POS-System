part of 'app_store.dart';

extension _AppStoreSplitSalesReturnsPart7 on AppStore {
  Future<CreditNote> cancelSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
  }) async {
    requirePermission(AppPermission.salesCancel);
    _requireSensitiveActionAuthorization(SensitiveAction.saleReverse);
    await _ensureCreditNotesLoaded();
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Cancelling a posted sale return requires the authoritative SQLite store.',
      );
    }

    const epsilon = 0.000001;
    final normalizedCreditNoteId = creditNoteId.trim();
    if (normalizedCreditNoteId.isEmpty) {
      throw ArgumentError('Credit note id is required.');
    }

    late CreditNote currentNote;
    late CreditNote updatedNote;
    late Sale sale;
    late Sale updatedSale;
    late int persistedNoteIndex;
    late List<CreditNote> authoritativeNotes;
    late String currentOperationReferenceId;
    late String currentJournalReferenceId;
    var oldReturnLedgerAmount = 0.0;

    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);

    await db.transaction(() async {
      final persistedCreditNotesRow = await db.customSelect(
        '''
        SELECT value FROM settings WHERE key = ?
        UNION ALL
        SELECT value FROM local_key_values WHERE key = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(AppStore._creditNotesKey),
          Variable<String>(AppStore._creditNotesKey),
        ],
      ).getSingleOrNull();
      final raw = persistedCreditNotesRow?.data['value']?.toString() ?? '';
      authoritativeNotes = <CreditNote>[];
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          authoritativeNotes = decoded
              .whereType<Map>()
              .map((item) =>
                  CreditNote.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      }
      persistedNoteIndex = authoritativeNotes.indexWhere(
        (note) => note.id == normalizedCreditNoteId,
      );
      if (persistedNoteIndex == -1) {
        throw StateError('Sale return credit note was not found.');
      }
      currentNote = authoritativeNotes[persistedNoteIndex];
      if (currentNote.version != expectedVersion) {
        throw StateError(
          'Sale return changed concurrently. Reload it before cancelling.',
        );
      }
      final status = currentNote.status.trim().toLowerCase();
      if (<String>{'cancelled', 'reversed', 'void'}.contains(status)) {
        throw StateError('This sale return is already cancelled.');
      }

      final saleIndex = _sales.indexWhere(
        (item) => item.id == currentNote.originalSaleId,
      );
      final loadedSale = saleIndex == -1
          ? await _saleByIdFromSqlite(currentNote.originalSaleId)
          : _sales[saleIndex];
      if (loadedSale == null) {
        throw StateError('Original sale for this return was not found.');
      }
      sale = loadedSale;

      final activeForSale = authoritativeNotes
          .where(
            (note) =>
                note.originalSaleId == sale.id &&
                !<String>{'cancelled', 'reversed', 'void'}
                    .contains(note.status.trim().toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (activeForSale.isEmpty || activeForSale.last.id != currentNote.id) {
        throw StateError(
          'Only the latest active return can be cancelled. Cancel newer returns first.',
        );
      }

      currentOperationReferenceId = currentNote.operationReferenceId.trim();
      if (currentOperationReferenceId.isEmpty) {
        currentOperationReferenceId =
            '${sale.id}:sale_return:${currentNote.date.microsecondsSinceEpoch}';
      }
      currentJournalReferenceId = currentNote.version <= 1
          ? currentNote.id
          : '${currentNote.id}:sale_return_edit:v${currentNote.version}';

      final allMovements = await BusinessSqliteStore.readStockMovements(db);
      final reversedIds = <String>{
        for (final movement in allMovements)
          if (movement.reversalOfMovementId.trim().isNotEmpty)
            movement.reversalOfMovementId.trim(),
      };
      final activeMovements = allMovements
          .where(
            (movement) =>
                movement.movementGroupId == currentOperationReferenceId &&
                movement.type == 'sale_return' &&
                movement.reversalOfMovementId.isNotEmpty &&
                !reversedIds.contains(movement.id),
          )
          .toList(growable: false);
      if (activeMovements.isEmpty &&
          currentNote.items.any((item) {
            final product = _findProductForSaleReturn(item.productId);
            return product?.trackStock ?? false;
          })) {
        throw StateError(
            'Active stock movements for this sale return are missing.');
      }
      for (final movement in activeMovements) {
        if (movement.batchId.trim().isEmpty) {
          throw StateError(
            'This historical sale return cannot be cancelled safely because its batch information is missing.',
          );
        }
        final balanceRow = await db.customSelect(
          '''
          SELECT COALESCE(quantity, 0) AS quantity
          FROM inventory_batch_balances
          WHERE store_id = ? AND warehouse_id = ?
            AND product_id = ? AND batch_id = ?
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(movement.warehouseId),
            Variable<String>(movement.productId),
            Variable<String>(movement.batchId),
          ],
        ).getSingleOrNull();
        final available =
            (balanceRow?.data['quantity'] as num? ?? 0).toDouble();
        if (available + epsilon < movement.quantity) {
          throw StateError(
            'Returned stock has moved downstream; reverse that movement first.',
          );
        }
      }

      await _requirePostedJournalInTransaction(
        db,
        referenceType: 'sale_return',
        referenceId: currentJournalReferenceId,
        failureMessage:
            'Active accounting journal for this sale return is missing.',
      );
      final returnAccountId = sale.customerId.trim().isNotEmpty
          ? sale.customerId.trim()
          : sale.customerName.trim();
      if (returnAccountId.isNotEmpty) {
        final currentLedgerId = currentNote.version <= 1
            ? '${sale.id}-sale-return-${currentNote.id}'
            : '${sale.id}-sale-return-${currentNote.id}-edit-v${currentNote.version}';
        final ledgerRow = await db.customSelect(
          '''
          SELECT debit, credit
          FROM account_transactions
          WHERE id = ? AND deleted_at = ''
          LIMIT 1
          ''',
          variables: <Variable<Object>>[Variable<String>(currentLedgerId)],
        ).getSingleOrNull();
        if (ledgerRow == null) {
          throw StateError(
              'Customer ledger entry for this sale return is missing.');
        }
        oldReturnLedgerAmount =
            ((ledgerRow.data['credit'] as num? ?? 0).toDouble() -
                    (ledgerRow.data['debit'] as num? ?? 0).toDouble())
                .abs();
      }

      final now = DateTime.now();
      for (final movement in activeMovements) {
        final product = _findProductById(movement.productId);
        if (product == null) {
          throw StateError('Returned product no longer exists.');
        }
        await batchService.reverseUnifiedMovementEffectInTransaction(
          product: product,
          warehouseId: movement.warehouseId,
          batchId: movement.batchId,
          movementQuantity: movement.quantity,
          unitCost: movement.unitCost,
          reversedAt: now,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await stockService.recordReversalInTransaction(
          originalMovement: movement,
          operationType: 'sale_return_cancel',
          documentType: 'sale_return',
          documentId: currentNote.id,
          reason: 'Sale return cancelled',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          syncTarget: _stockTransactionSyncTarget,
        );
        await batchService.assertWarehouseBatchBalanceInTransaction(
          productId: movement.productId,
          warehouseId: movement.warehouseId,
          storeId: appIdentity.storeId,
        );
      }

      await AccountingService.reverseEntryForReference(
        referenceType: 'sale_return',
        referenceId: currentNote.id,
        reason: 'Sale return cancelled',
        createdBy: _deviceId,
        adjustCashLocationBalance: false,
        notifyChange: false,
        withinExistingTransaction: true,
      );
      final remainingJournal = await db.customSelect(
        '''
        SELECT id
        FROM journal_entries je
        WHERE je.reference_type = 'sale_return'
          AND je.reference_id = ?
          AND je.deleted_at = '' AND je.status = 'posted'
          AND NOT EXISTS (
            SELECT 1 FROM journal_entries rev
            WHERE rev.reversed_entry_id = je.id
              AND rev.deleted_at = '' AND rev.status = 'posted'
          )
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(currentJournalReferenceId),
        ],
      ).getSingleOrNull();
      if (remainingJournal != null) {
        throw StateError('Sale return accounting reversal did not complete.');
      }

      updatedNote = currentNote.copyWith(
        status: 'Cancelled',
        note: 'Cancelled on ${now.toIso8601String()}',
        version: currentNote.version + 1,
        updatedAt: now,
      );
      authoritativeNotes[persistedNoteIndex] = updatedNote;

      final activeAfterCancellation = authoritativeNotes
          .where(
            (note) =>
                note.originalSaleId == sale.id &&
                !<String>{'cancelled', 'reversed', 'void'}
                    .contains(note.status.trim().toLowerCase()),
          )
          .toList(growable: false);
      final returnedByProduct = <String, double>{};
      var totalReturnedAmount = 0.0;
      for (final note in activeAfterCancellation) {
        totalReturnedAmount += note.amount;
        for (final item in note.items) {
          returnedByProduct.update(
            item.productId,
            (value) => value + item.quantity,
            ifAbsent: () => item.quantity,
          );
        }
      }
      final originalByProduct = <String, double>{};
      for (final item in sale.items) {
        originalByProduct.update(
          item.productId,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
      final isFullReturn = originalByProduct.entries.every(
        (entry) =>
            (entry.value - (returnedByProduct[entry.key] ?? 0)).abs() <=
            epsilon,
      );
      final originalSnapshot = sale.postedSnapshot;
      final restoredPaid = originalSnapshot?.totals.paid ?? sale.paidAmount;
      final restoredPaymentStatus =
          originalSnapshot?.paymentStatus ?? sale.paymentStatus;
      final restoredCashReceived =
          (originalSnapshot?.extra['cashReceivedAmount'] as num?)?.toDouble() ??
              sale.cashReceivedAmount;
      final restoredPaidInPaymentCurrency =
          (originalSnapshot?.extra['paidAmountInPaymentCurrency'] as num?)
                  ?.toDouble() ??
              sale.paidAmountInPaymentCurrency;
      final restoredCashInPaymentCurrency = (originalSnapshot
                  ?.extra['cashReceivedAmountInPaymentCurrency'] as num?)
              ?.toDouble() ??
          sale.cashReceivedAmountInPaymentCurrency;
      final restoredPaidBase =
          (originalSnapshot?.extra['paidBaseAmount'] as num?)?.toDouble() ??
              sale.paidBaseAmount;
      final restoredExchangeDifference =
          (originalSnapshot?.extra['exchangeDifferenceAmount'] as num?)
                  ?.toDouble() ??
              sale.exchangeDifferenceAmount;
      final restoredStatus = originalSnapshot?.status ?? 'Paid';
      updatedSale = _saleSyncMetaPreview(
        sale.copyWith(
          status: activeAfterCancellation.isEmpty
              ? restoredStatus
              : (isFullReturn ? 'Returned' : 'Partially Returned'),
          paymentStatus: activeAfterCancellation.isEmpty
              ? restoredPaymentStatus
              : (isFullReturn ? 'returned' : restoredPaymentStatus),
          paidAmount: activeAfterCancellation.isEmpty || !isFullReturn
              ? restoredPaid
              : 0,
          cashReceivedAmount: activeAfterCancellation.isEmpty || !isFullReturn
              ? restoredCashReceived
              : 0,
          paidAmountInPaymentCurrency:
              activeAfterCancellation.isEmpty || !isFullReturn
                  ? restoredPaidInPaymentCurrency
                  : 0,
          cashReceivedAmountInPaymentCurrency:
              activeAfterCancellation.isEmpty || !isFullReturn
                  ? restoredCashInPaymentCurrency
                  : 0,
          paidBaseAmount: activeAfterCancellation.isEmpty || !isFullReturn
              ? restoredPaidBase
              : 0,
          exchangeDifferenceAmount:
              activeAfterCancellation.isEmpty || !isFullReturn
                  ? restoredExchangeDifference
                  : 0,
          returnedAmount: totalReturnedAmount,
          note: 'Return cancelled on ${now.toIso8601String()}',
        ),
        now,
      );

      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._salesKey,
        <Map<String, dynamic>>[updatedSale.toJson()],
        sortIndices: const <int?>[0],
      );
      await BusinessSqliteStore.saveKeyJson(
        db,
        AppStore._creditNotesKey,
        jsonEncode(authoritativeNotes.map((item) => item.toJson()).toList()),
      );
      if (returnAccountId.isNotEmpty && oldReturnLedgerAmount > epsilon) {
        await _persistAccountTransactionInExistingTransaction(
          db,
          AccountTransaction(
            id: '${sale.id}-sale-return-${currentNote.id}-cancel-v${updatedNote.version}',
            accountType: 'customer',
            accountId: returnAccountId,
            accountName: sale.customerName,
            date: now,
            type: 'saleReturnCancel',
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: oldReturnLedgerAmount,
            currency: sale.invoiceCurrency,
            note: 'Cancelled sale return ${currentNote.creditNoteNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ),
        );
      }
    });

    final noteIndex = _creditNotes.indexWhere(
      (note) => note.id == normalizedCreditNoteId,
    );
    if (noteIndex == -1) {
      _creditNotes.add(updatedNote);
    } else {
      _creditNotes[noteIndex] = updatedNote;
    }
    final saleIndex = _sales.indexWhere((item) => item.id == sale.id);
    if (saleIndex != -1) {
      _sales[saleIndex] = updatedSale;
      _touchDataRevisions(sales: true);
    }
    _recordSyncChange(
      entityType: 'sale',
      entityId: sale.id,
      operation: 'cancel_return',
      payload: updatedSale.toJson(),
    );
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await _refreshProductStockCompatibilityCache(
      currentNote.items.map((item) => item.productId),
    );
    await _refreshAccountTransactionsFromSqlite();
    await _saveDirty(sync: true);
    AccountingService.notifyCommittedMutation();
    notifyListeners();
    return updatedNote;
  }
}
